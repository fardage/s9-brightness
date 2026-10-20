import Foundation
import Testing
@testable import S9Brightness

struct SSDPReplyTests {
    private let types = [MonitorDiscovery.ipControlType, MonitorDiscovery.rendererType]

    @Test func parsesMatchingReply() {
        let text = """
            HTTP/1.1 200 OK\r
            CACHE-CONTROL: max-age=1800\r
            Location: http://192.0.2.10:9110/ip_control\r
            ST: urn:samsung.com:device:IPControlServer:1\r
            \r

            """
        let reply = MonitorDiscovery.parseSSDPReply(text, types: types)
        #expect(reply?.host == "192.0.2.10")
        #expect(reply?.st == MonitorDiscovery.ipControlType)
        #expect(reply?.location.absoluteString == "http://192.0.2.10:9110/ip_control")
    }

    @Test func ignoresOtherSearchTargets() {
        let text = "HTTP/1.1 200 OK\r\nLOCATION: http://192.0.2.20:80/desc\r\nST: urn:schemas-upnp-org:device:Basic:1\r\n\r\n"
        #expect(MonitorDiscovery.parseSSDPReply(text, types: types) == nil)
    }

    @Test func ignoresReplyWithoutLocation() {
        let text = "HTTP/1.1 200 OK\r\nST: \(MonitorDiscovery.rendererType)\r\n\r\n"
        #expect(MonitorDiscovery.parseSSDPReply(text, types: types) == nil)
    }
}

struct DescriptionTests {
    private func description(manufacturer: String = "Samsung Electronics", category: String = "Display.TV.LCD Multimedia.DMR",
                             name: String = "27&quot; ViewFinity S9") -> Data {
        Data("""
            <?xml version="1.0"?>
            <root xmlns="urn:schemas-upnp-org:device-1-0" xmlns:df="http://schemas.microsoft.com/windows/2008/09/devicefoundation">
              <device>
                <df:X_deviceCategory>\(category)</df:X_deviceCategory>
                <friendlyName>\(name)</friendlyName>
                <manufacturer>\(manufacturer)</manufacturer>
                <modelDescription>Samsung TV DMR</modelDescription>
                <modelName>LS27C902PAUXEN</modelName>
                <serialNumber>TESTSERIAL</serialNumber>
              </device>
            </root>
            """.utf8)
    }

    @Test func ipControlDescription() throws {
        let monitor = try #require(MonitorDiscovery.parseDescription(description(), host: "192.0.2.10", ipControl: true))
        #expect(monitor.name == "27\" ViewFinity S9")
        #expect(monitor.model == "LS27C902PAUXEN")
        #expect(monitor.serial == "TESTSERIAL")
        #expect(monitor.ipControl)
        #expect(monitor.id == "TESTSERIAL")
    }

    @Test func samsungRendererIsMonitorWithIPRemoteOff() throws {
        let monitor = try #require(MonitorDiscovery.parseDescription(description(), host: "192.0.2.10", ipControl: false))
        #expect(!monitor.ipControl)
    }

    @Test func otherRenderersAreIgnored() {
        #expect(MonitorDiscovery.parseDescription(description(manufacturer: "Sonos, Inc."), host: "192.0.2.30", ipControl: false) == nil)
    }

    @Test func invalidXMLIsIgnored() {
        #expect(MonitorDiscovery.parseDescription(Data("<root>".utf8), host: "192.0.2.10", ipControl: true) == nil)
    }

    @Test func externalEntitiesAreNotResolved() throws {
        let secret = FileManager.default.temporaryDirectory.appending(path: "s9-xxe-\(UUID().uuidString).txt")
        try "SECRET".write(to: secret, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: secret) }
        let xml = """
            <?xml version="1.0"?><!DOCTYPE r [<!ENTITY x SYSTEM "\(secret.absoluteString)">]>
            <root><device><friendlyName>&x;</friendlyName></device></root>
            """
        let monitor = MonitorDiscovery.parseDescription(Data(xml.utf8), host: "192.0.2.66", ipControl: true)
        #expect(monitor?.name.contains("SECRET") != true)
    }
}
