import Testing
import AppKit
@testable import DesignSystem

@MainActor struct BrandTests {
    func pixels(_ image: NSImage, size: Int) -> [UInt8] {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size)); NSGraphicsContext.restoreGraphicsState()
        return Array(UnsafeBufferPointer(start: rep.bitmapData!, count: size * size * 4))
    }
    @Test func appIconWritesA1024PNGWithTransparentCorners() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("brand-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try Brand.writeIconPNG(to: url)
        let rep = try #require(NSBitmapImageRep(data: Data(contentsOf: url)))
        #expect(rep.pixelsWide == 1024 && rep.pixelsHigh == 1024)
        #expect(rep.colorAt(x: 4, y: 4)!.alphaComponent < 0.05)
        #expect(rep.colorAt(x: 512, y: 200)!.alphaComponent > 0.99)
    }
    @Test func focusDotIsTheAccentBlueAndNeverPurple() {
        let data = pixels(Brand.iconImage(size: 256), size: 256)
        let center = (128 * 256 + 128) * 4
        let (r, g, b) = (Int(data[center]), Int(data[center + 1]), Int(data[center + 2]))
        #expect(b > 200 && b > r + 80 && g > r, "focus dot should read as blue, got \(r),\(g),\(b)")
    }
    @Test func menuBarImageIsATemplateWithVisibleGlyph() {
        let image = Brand.menuBarImage()
        #expect(image.isTemplate)
        #expect(image.size == NSSize(width: 18, height: 18))
        let alpha = stride(from: 3, to: pixels(image, size: 36).count, by: 4).map { pixels(image, size: 36)[$0] }
        #expect(alpha.filter { $0 > 128 }.count > 60)
    }
}
