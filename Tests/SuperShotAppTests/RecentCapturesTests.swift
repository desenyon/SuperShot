import Capture
import CoreGraphics
import Testing
@testable import SuperShotApp

@MainActor struct RecentCapturesTests {
    @Test func recentIsOrderedBoundedAndKeepsTheOriginalIdentity() throws {
        let surface = try #require(CGContext(data: nil, width: 12, height: 12, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(surface.makeImage())
        let recent = RecentCaptures(maxCount: 2)
        let a = CapturedImage(image: image, scale: 1, source: "Area")
        let b = CapturedImage(image: image, scale: 1, source: "Window")
        let c = CapturedImage(image: image, scale: 1, source: "Screen")
        recent.insert(a, disposable: false)
        recent.insert(b, disposable: true)
        recent.insert(c, disposable: false)
        #expect(recent.entries.map(\.id) == [c.id, b.id])
        recent.markKept(b.id)
        #expect(recent.entries.allSatisfy { !$0.disposable })
    }
}
