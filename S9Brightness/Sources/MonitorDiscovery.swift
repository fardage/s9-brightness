import Foundation

struct DiscoveredMonitor: Identifiable {
    var host: String
    var name: String
    var model: String?
    var serial: String?
    /// false: a Samsung display that answers UPnP but has IP Remote turned off.
    var ipControl: Bool

    var id: String { serial ?? host }
}

/// Finds Samsung displays via SSDP. A monitor with IP Remote enabled advertises an
/// IPControlServer device; one with it disabled only shows up as a MediaRenderer.
enum MonitorDiscovery {
    static let ipControlType = "urn:samsung.com:device:IPControlServer:1"
    static let rendererType = "urn:schemas-upnp-org:device:MediaRenderer:1"
    /// Where the IP Remote switch lives in the monitor's own menu.
    static let ipRemoteMenuPath = "Settings › Connection › Network › Expert Settings"

    static func search(timeout: TimeInterval = 3) async -> [DiscoveredMonitor] {
        // The search blocks on recv(), so keep it off Swift's cooperative thread pool.
        let replies = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: ssdpSearch(types: [ipControlType, rendererType], timeout: timeout))
            }
        }

        var locations: [String: (ipControl: URL?, renderer: URL?)] = [:]
        for reply in replies {
            if reply.st == ipControlType {
                locations[reply.host, default: (nil, nil)].ipControl = reply.location
            } else {
                locations[reply.host, default: (nil, nil)].renderer = reply.location
            }
        }

        var found: [DiscoveredMonitor] = []
        await withTaskGroup(of: DiscoveredMonitor?.self) { group in
            for (host, loc) in locations {
                group.addTask { await describe(host: host, ipControl: loc.ipControl, renderer: loc.renderer) }
            }
            for await monitor in group {
                if let monitor { found.append(monitor) }
            }
        }
        return found.sorted { ($0.name, $0.host) < ($1.name, $1.host) }
    }

    /// Describes a manually entered host, using the port the IP Control device is advertised on.
    static func describe(host: String) async -> DiscoveredMonitor? {
        await describe(host: host, ipControl: URL(string: "http://\(host):9110/ip_control"), renderer: nil)
    }

    private static func describe(host: String, ipControl: URL?, renderer: URL?) async -> DiscoveredMonitor? {
        if let ipControl, let data = await fetch(ipControl),
           let monitor = parseDescription(data, host: host, ipControl: true) {
            return monitor
        }
        guard let renderer, let data = await fetch(renderer) else { return nil }
        return parseDescription(data, host: host, ipControl: false)
    }

    /// Builds a monitor from a UPnP device description. An IPControlServer description is
    /// always a monitor; a MediaRenderer description only counts if it's a Samsung display.
    static func parseDescription(_ data: Data, host: String, ipControl: Bool) -> DiscoveredMonitor? {
        // Descriptions come from any device on the network: never resolve external entities.
        guard let xml = try? XMLDocument(data: data, options: .nodeLoadExternalEntitiesNever) else { return nil }
        if !ipControl {
            guard value("manufacturer", in: xml)?.contains("Samsung") == true,
                  value("X_deviceCategory", in: xml)?.contains("Display") == true
                    || value("modelDescription", in: xml)?.contains("TV") == true else { return nil }
        }
        return DiscoveredMonitor(host: host, name: value("friendlyName", in: xml) ?? host,
                                 model: value("modelName", in: xml), serial: value("serialNumber", in: xml),
                                 ipControl: ipControl)
    }

    private static func fetch(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        return try? await URLSession.shared.data(for: request).0
    }

    /// First element with this local name, ignoring namespace prefixes such as `df:`.
    private static func value(_ name: String, in xml: XMLDocument) -> String? {
        (try? xml.nodes(forXPath: "//*[local-name()='\(name)']"))?.first?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    struct SSDPReply: Equatable {
        let host: String
        let st: String
        let location: URL
    }

    /// Parses one SSDP response; nil unless it's for one of `types` and has a usable LOCATION.
    static func parseSSDPReply(_ text: String, types: [String]) -> SSDPReply? {
        var headers: [String: String] = [:]
        for line in text.components(separatedBy: "\r\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].trimmingCharacters(in: .whitespaces).uppercased()] =
                line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard let st = headers["ST"], types.contains(st),
              let location = headers["LOCATION"].flatMap(URL.init(string:)),
              let host = location.host else { return nil }
        return SSDPReply(host: host, st: st, location: location)
    }

    /// Blocking SSDP M-SEARCH; run off the main thread.
    private static func ssdpSearch(types: [String], timeout: TimeInterval) -> [SSDPReply] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return [] }
        defer { close(fd) }

        var ttl: UInt8 = 2
        setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<UInt8>.size))
        var tv = timeval(tv_sec: 0, tv_usec: 250_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var dest = sockaddr_in()
        dest.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_port = in_port_t(1900).bigEndian
        dest.sin_addr.s_addr = inet_addr("239.255.255.250")

        // UDP is lossy, so send each search twice.
        for _ in 0..<2 {
            for st in types {
                let bytes = Array("M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: \(st)\r\n\r\n".utf8)
                withUnsafePointer(to: dest) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { addr in
                        _ = sendto(fd, bytes, bytes.count, 0, addr, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }

        var replies: [SSDPReply] = []
        var buffer = [UInt8](repeating: 0, count: 4096)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let n = recv(fd, &buffer, buffer.count, 0)
            guard n > 0,
                  let reply = parseSSDPReply(String(decoding: buffer[0..<n], as: UTF8.self), types: types) else { continue }
            replies.append(reply)
        }
        return replies
    }
}
