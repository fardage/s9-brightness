import Testing
@testable import S9Brightness

struct UpdateCheckerTests {
    @Test(arguments: [("1.3", "1.2.2"), ("1.10", "1.9"), ("2.0", "1.9.9"), ("1.2.3", "1.2")])
    func newer(_ version: String, _ current: String) {
        #expect(UpdateChecker.isNewer(version, than: current))
    }

    @Test(arguments: [("1.2.2", "1.2.2"), ("1.2.1", "1.2.2"), ("1.9", "1.10")])
    func notNewer(_ version: String, _ current: String) {
        #expect(!UpdateChecker.isNewer(version, than: current))
    }
}
