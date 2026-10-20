import CryptoKit
import Foundation

/// The pairing's non-secret part, stored in monitor.json; the token lives in the keychain.
struct IPControlConfig: Codable {
    var host: String
    var cert_sha256: String?
    /// UPnP serial number, used to find the monitor again if its IP changes.
    var serial: String?
    var name: String?

    static let url = URL.applicationSupportDirectory.appending(path: "S9Brightness/monitor.json")

    static func load() -> IPControlConfig? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(IPControlConfig.self, from: data)
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: Self.url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.url.path)
    }
}

enum IPControlError: LocalizedError {
    case notPaired
    case unauthorized(String)
    case certificateChanged
    case unreachable(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notPaired: return "Not paired"
        case .unauthorized(let m): return "Not authorized (\(m)); pair again"
        case .certificateChanged: return "Monitor certificate changed; pair again if expected"
        case .unreachable(let m): return "Monitor unreachable: \(m)"
        case .server(let m): return "Monitor error: \(m)"
        }
    }
}

/// Accepts the monitor's self-signed certificate only if it matches the pinned fingerprint
/// (or records the fingerprint when pairing, when nothing is pinned yet).
private final class PinningDelegate: NSObject, URLSessionDelegate {
    let pinned: String?
    private(set) var observed: String?
    private(set) var mismatch = false

    init(pinned: String?) { self.pinned = pinned }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let der = SecCertificateCopyData(leaf) as Data
        let fingerprint = SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
        observed = fingerprint
        if let pinned, pinned != fingerprint {
            mismatch = true
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

/// Samsung consumer IP Control client (HTTPS JSON-RPC 2.0 on TCP 1516).
@MainActor
final class IPControlClient {
    static let port = 1516
    static let nativeMax = 50

    private(set) var config = IPControlConfig.load()
    private var token = Keychain.readToken()
    private var session: URLSession?

    var isPaired: Bool { config != nil && token != nil }

    func getBacklight() async throws -> Int {
        try await backlight(nil)
    }

    func setBacklight(_ native: Int) async throws -> Int {
        try await backlight(max(0, min(Self.nativeMax, native)))
    }

    /// Points the existing pairing at a new address (the monitor got a new IP).
    func updateHost(_ host: String) throws {
        guard var config else { throw IPControlError.notPaired }
        config.host = host
        try config.save()
        self.config = config
        resetSession()
    }

    /// Requests a new token; the user must accept the prompt on the monitor (~60 s timeout).
    func pair(host: String, serial: String?, name: String?) async throws {
        let session = Self.makeSession(pinned: nil, timeout: 75)
        defer { session.finishTasksAndInvalidate() }
        let result = try await rpc(session: session, host: host, method: "createAccessToken", params: nil)
        guard let token = result["AccessToken"] as? String else {
            throw IPControlError.server("no token in reply")
        }
        let config = IPControlConfig(host: host, cert_sha256: (session.delegate as? PinningDelegate)?.observed,
                                     serial: serial, name: name)
        try Keychain.saveToken(token)
        try config.save()
        self.config = config
        self.token = token
        resetSession()
    }

    private static func makeSession(pinned: String?, timeout: TimeInterval) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        return URLSession(configuration: configuration, delegate: PinningDelegate(pinned: pinned), delegateQueue: nil)
    }

    /// The host can come from the network (SSDP) or user input, so validate it instead of force-unwrapping.
    static func endpoint(host: String) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        // IPv6 literals need brackets in a URL.
        components.host = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        components.port = port
        components.path = "/"
        guard !host.isEmpty, let url = components.url else { throw IPControlError.unreachable("invalid address \(host)") }
        return url
    }

    private func resetSession() {
        session?.invalidateAndCancel()
        session = nil
    }

    private func backlight(_ native: Int?) async throws -> Int {
        guard let config, let token else { throw IPControlError.notPaired }
        let session = self.session ?? Self.makeSession(pinned: config.cert_sha256, timeout: 5)
        self.session = session
        var params: [String: Any] = ["AccessToken": token]
        if let native { params["backlight"] = native }
        let result = try await rpc(session: session, host: config.host, method: "backlightControl", params: params)
        guard let value = (result["backlight"] as? NSNumber)?.intValue else {
            throw IPControlError.server("unexpected reply")
        }
        return value
    }

    private func rpc(session: URLSession, host: String, method: String, params: [String: Any]?) async throws -> [String: Any] {
        var body: [String: Any] = ["jsonrpc": "2.0", "id": "1", "method": method]
        if let params { body["params"] = params }
        var request = URLRequest(url: try Self.endpoint(host: host))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        do {
            (data, _) = try await session.data(for: request)
        } catch {
            if (session.delegate as? PinningDelegate)?.mismatch == true { throw IPControlError.certificateChanged }
            throw IPControlError.unreachable(error.localizedDescription)
        }
        return try Self.parseReply(data)
    }

    /// Returns the JSON-RPC result, or throws the error the monitor reported.
    static func parseReply(_ data: Data) throws -> [String: Any] {
        guard let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw IPControlError.server("invalid JSON")
        }
        // Errors arrive either in a JSON-RPC envelope or as a bare {"code", "message"};
        // an invalid token shows up as -32700 "Parse error" on current firmware.
        let err = (reply["error"] as? [String: Any]) ?? (reply["result"] == nil && reply["code"] != nil ? reply : nil)
        if let err {
            let code = (err["code"] as? NSNumber)?.intValue ?? 0
            let message = err["message"] as? String ?? "error \(code)"
            if code == -32010 || code == -32700 { throw IPControlError.unauthorized(message) }
            throw IPControlError.server("\(message) (\(code))")
        }
        return reply["result"] as? [String: Any] ?? [:]
    }
}
