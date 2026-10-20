import Foundation
import Testing
@testable import S9Brightness

struct PresetsTests {
    /// A throwaway defaults domain so tests never touch the app's real presets.
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suite = "PresetsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    @Test func defaultsWhenNothingStored() {
        withDefaults { defaults in
            #expect(Presets.load(from: defaults).values == Presets.defaultValues)
        }
    }

    @Test func defaultValuesAreReachableLevels() {
        #expect(Presets.defaultValues.allSatisfy { Presets.normalize($0) == $0 })
    }

    @Test func saveAndLoadRoundTrip() {
        withDefaults { defaults in
            var presets = Presets()
            presets.update(0, to: 20)
            presets.update(3, to: 90)
            presets.save(to: defaults)
            #expect(Presets.load(from: defaults).values == [20, 40, 70, 90])
        }
    }

    @Test func invalidStoredValuesFallBackToDefaults() {
        withDefaults { defaults in
            defaults.set([1, 2], forKey: "presets")
            #expect(Presets.load(from: defaults).values == Presets.defaultValues)
            defaults.set("garbage", forKey: "presets")
            #expect(Presets.load(from: defaults).values == Presets.defaultValues)
        }
    }

    @Test(arguments: [(41, 42), (33, 34), (-5, 0), (130, 100), (0, 0), (100, 100)])
    func normalizesToMonitorSteps(_ input: Int, _ expected: Int) {
        #expect(Presets.normalize(input) == expected)
    }

    @Test func storedValuesAreNormalized() {
        #expect(Presets(values: [41, -5, 130, 50]).values == [42, 0, 100, 50])
    }

    @Test func updateIgnoresOutOfRangeIndex() {
        var presets = Presets()
        presets.update(7, to: 20)
        #expect(presets == Presets())
    }
}
