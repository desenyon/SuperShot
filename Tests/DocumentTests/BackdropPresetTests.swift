import Document
import Foundation
import Testing

struct BackdropPresetTests {
    @Test func presetTransferPreservesWatermarkAndRejectsInvalidGeometry() throws {
        var backdrop = Backdrop()
        backdrop.fill = .gradient
        backdrop.watermark = ImageWatermark(text: "Internal review", anchor: CGPoint(x: 0.5, y: 1))
        let preset = BackdropPreset(name: "Review", backdrop: backdrop)
        #expect(try BackdropPresetTransfer.decode(BackdropPresetTransfer.encode(preset)) == preset)
        backdrop.watermark?.opacity = 1.4
        let invalid = BackdropPreset(name: "Invalid", backdrop: backdrop)
        #expect(throws: ProjectFile.Error.invalidGeometry) {
            try BackdropPresetTransfer.decode(BackdropPresetTransfer.encode(invalid))
        }
    }
}
