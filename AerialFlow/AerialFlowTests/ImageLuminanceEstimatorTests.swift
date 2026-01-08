import Testing
import Foundation
@testable import AerialFlow

struct ImageLuminanceEstimatorTests {
    @Test func testBlackIsNearZero() throws {
        let data = try TestImageFactory.pngData(rgba: (0, 0, 0, 255))
        let value = ImageLuminanceEstimator.brightness(from: data)
        #expect(value != nil)
        #expect(value! < 0.05)
    }

    @Test func testWhiteIsNearOne() throws {
        let data = try TestImageFactory.pngData(rgba: (255, 255, 255, 255))
        let value = ImageLuminanceEstimator.brightness(from: data)
        #expect(value != nil)
        #expect(value! > 0.95)
    }

    @Test func testInvalidImageReturnsNil() {
        let junk = Data([0x00, 0x01, 0x02, 0x03, 0x04])
        #expect(ImageLuminanceEstimator.brightness(from: junk) == nil)
    }
}


