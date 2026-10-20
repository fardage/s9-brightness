import Testing
@testable import S9Brightness

@MainActor
struct BrightnessConversionTests {
    @Test func nativeRangeMapsToPercent() {
        #expect(BrightnessModel.toPercent(0) == 0)
        #expect(BrightnessModel.toPercent(12) == 24)
        #expect(BrightnessModel.toPercent(IPControlClient.nativeMax) == 100)
    }

    @Test func percentMapsToNative() {
        #expect(BrightnessModel.toNative(0) == 0)
        #expect(BrightnessModel.toNative(24) == 12)
        #expect(BrightnessModel.toNative(100) == IPControlClient.nativeMax)
    }

    @Test func roundTripsEverySliderStep() {
        for percent in stride(from: 0.0, through: 100, by: 2) {
            #expect(BrightnessModel.toPercent(BrightnessModel.toNative(percent)) == percent)
        }
    }
}
