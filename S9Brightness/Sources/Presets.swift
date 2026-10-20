import Foundation

/// The four brightness presets shown in the menu, stored in UserDefaults.
struct Presets: Equatable {
    /// Must be multiples of 2, since the monitor's backlight has 2 % steps.
    static let defaultValues = [10, 40, 70, 100]
    private static let key = "presets"

    private(set) var values: [Int]

    init(values: [Int] = Presets.defaultValues) {
        // Anything that isn't exactly four slots (e.g. corrupted defaults) falls back to the defaults.
        self.values = values.count == Self.defaultValues.count ? values.map(Self.normalize) : Self.defaultValues
    }

    /// Clamps to 0–100 and rounds to the monitor's 2 % steps.
    static func normalize(_ percent: Int) -> Int {
        min(100, max(0, Int((Double(percent) / 2).rounded()) * 2))
    }

    mutating func update(_ index: Int, to percent: Int) {
        guard values.indices.contains(index) else { return }
        values[index] = Self.normalize(percent)
    }

    static func load(from defaults: UserDefaults = .standard) -> Presets {
        Presets(values: defaults.array(forKey: key) as? [Int] ?? defaultValues)
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(values, forKey: Self.key)
    }
}
