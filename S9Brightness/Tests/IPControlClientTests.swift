import Foundation
import Testing
@testable import S9Brightness

@MainActor
struct EndpointTests {
    @Test func ipv4() throws {
        #expect(try IPControlClient.endpoint(host: "192.0.2.10").absoluteString == "https://192.0.2.10:1516/")
    }

    @Test func hostname() throws {
        #expect(try IPControlClient.endpoint(host: "monitor.local").absoluteString == "https://monitor.local:1516/")
    }

    @Test func ipv6IsBracketed() throws {
        #expect(try IPControlClient.endpoint(host: "2001:db8::1").absoluteString == "https://[2001:db8::1]:1516/")
        #expect(try IPControlClient.endpoint(host: "[2001:db8::1]").absoluteString == "https://[2001:db8::1]:1516/")
    }

    @Test(arguments: ["a b", "evil/x", "", "host?x=1"])
    func invalidHostThrows(_ host: String) {
        #expect(throws: IPControlError.self) { try IPControlClient.endpoint(host: host) }
    }
}

@MainActor
struct ReplyParsingTests {
    private func parse(_ json: String) throws -> [String: Any] {
        try IPControlClient.parseReply(Data(json.utf8))
    }

    private func error(_ json: String) -> IPControlError? {
        do {
            _ = try parse(json)
            return nil
        } catch {
            return error as? IPControlError
        }
    }

    @Test func result() throws {
        let result = try parse(#"{"jsonrpc":"2.0","id":"1","result":{"backlight":12}}"#)
        #expect((result["backlight"] as? NSNumber)?.intValue == 12)
    }

    @Test func pairingDeclinedIsUnauthorized() {
        guard case .unauthorized? = error(#"{"jsonrpc":"2.0","id":"1","error":{"code":-32010,"message":"Unauthorized access"}}"#) else {
            Issue.record("expected unauthorized")
            return
        }
    }

    @Test func invalidTokenBareErrorIsUnauthorized() {
        guard case .unauthorized? = error(#"{"code":-32700,"message":"Parse error"}"#) else {
            Issue.record("expected unauthorized")
            return
        }
    }

    @Test func otherErrorIsServerError() {
        guard case .server(let message)? = error(#"{"jsonrpc":"2.0","id":"1","error":{"code":-32601,"message":"Method not found"}}"#) else {
            Issue.record("expected server error")
            return
        }
        #expect(message.contains("-32601"))
    }

    @Test func invalidJSONIsServerError() {
        guard case .server? = error("not json") else {
            Issue.record("expected server error")
            return
        }
    }
}

struct ConfigTests {
    @Test func decodesStoredPairingFile() throws {
        let json = #"{"host":"192.0.2.10","cert_sha256":"abc","serial":"TESTSERIAL","name":"27\" ViewFinity S9"}"#
        let config = try JSONDecoder().decode(IPControlConfig.self, from: Data(json.utf8))
        #expect(config.host == "192.0.2.10")
        #expect(config.cert_sha256 == "abc")
        #expect(config.serial == "TESTSERIAL")
        #expect(config.name == "27\" ViewFinity S9")
    }

    @Test func optionalFieldsMayBeMissing() throws {
        let config = try JSONDecoder().decode(IPControlConfig.self, from: Data(#"{"host":"192.0.2.10"}"#.utf8))
        #expect(config.serial == nil && config.cert_sha256 == nil)
    }
}
