import CoreGraphics
import Testing
@testable import Capture

struct RecordingSourceTests {
    @Test func validatesLocalCropAgainstShiftedDisplay() throws {
        let display = CGRect(x: -1440, y: 220, width: 1440, height: 900)
        let crop = try #require(RecordingSourceGeometry.crop(CGRect(x: 1280, y: 780, width: 300, height: 240), on: display))
        #expect(crop == CGRect(x: 1280, y: 780, width: 160, height: 120))
        #expect(RecordingSourceGeometry.crop(CGRect(x: 1460, y: 30, width: 100, height: 100), on: display) == nil)
        #expect(RecordingSourceGeometry.crop(CGRect(x: 0, y: 0, width: 1, height: 100), on: display) == nil)
    }

    @Test func productionResolutionUsesCropAspectAndEvenPixels() {
        let portrait = CGSize(width: 1440, height: 2560)
        #expect(RecordingDimensions(pixels: portrait, resolution: .fullHD) == RecordingDimensions(width: 1080, height: 1920))
        #expect(RecordingDimensions(pixels: CGSize(width: 2561, height: 1441), resolution: .hd) == RecordingDimensions(width: 1278, height: 720))
        #expect(RecordingDimensions(pixels: CGSize(width: 640, height: 360), resolution: .fullHD) == RecordingDimensions(width: 640, height: 360))
        #expect(RecordingDimensions(pixels: CGSize(width: CGFloat.infinity, height: 100), resolution: .automatic) == nil)
    }

    @Test func previewBoundsAndClickZoomShareTheSelectedRegion() {
        let display = CGRect(x: -1440, y: 220, width: 1440, height: 900)
        let crop = CGRect(x: 160, y: 100, width: 800, height: 480)
        #expect(RecordingSourceGeometry.appKitBounds(of: crop, on: display) == CGRect(x: -1280, y: 540, width: 800, height: 480))
        #expect(RecordingSourceGeometry.previewPixels(for: crop.size) == CGSize(width: 320, height: 192))
        #expect(RecordingSourceGeometry.previewPixels(for: .zero) == nil)
    }
}
