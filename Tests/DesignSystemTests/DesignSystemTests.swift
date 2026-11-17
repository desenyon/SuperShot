import Testing
import Foundation
@testable import DesignSystem

final class DesignSystemTests {
    @Test func pinResizePreservesAspectAndOppositeCorner() {
        let frame = CGRect(x: 50, y: 70, width: 400, height: 200)
        let result = PinGeometry.resize(frame, edges: [.left, .bottom], delta: CGPoint(x: -100, y: -50), available: CGSize(width: 1200, height: 800))
        #expect(result.size == CGSize(width: 500, height: 250))
        #expect(result.maxX == frame.maxX && result.maxY == frame.maxY)
        let right = PinGeometry.resize(frame, edges: .right, delta: CGPoint(x: 100, y: 0), available: CGSize(width: 1200, height: 800))
        #expect(right.minX == frame.minX && right.midY == frame.midY)
        #expect(right.width / right.height == 2)
    }
    @Test func pinResizeClampsWithoutFlippingAndFitsPortraitImages() {
        let frame = CGRect(x: 0, y: 0, width: 400, height: 200)
        let small = PinGeometry.resize(frame, edges: .right, delta: CGPoint(x: -10000, y: 0), available: CGSize(width: 1200, height: 800))
        #expect(small.width == DS.pinMinimumLongEdge && small.height > 0)
        let large = PinGeometry.resize(frame, edges: .top, delta: CGPoint(x: 0, y: 10000), available: CGSize(width: 600, height: 400))
        #expect(large.size == CGSize(width: 600, height: 300))
        let tall = PinGeometry.fittedSize(image: CGSize(width: 1000, height: 10000), longestEdge: 520, available: CGSize(width: 800, height: 400))
        #expect(tall == CGSize(width: 40, height: 400))
    }
    @Test func pinEdgesRespectAppKitCoordinates() {
        let size = CGSize(width: 400, height: 200)
        #expect(PinGeometry.edges(at: CGPoint(x: 1, y: 1), size: size) == [.left, .bottom])
        #expect(PinGeometry.edges(at: CGPoint(x: 399, y: 199), size: size) == [.right, .top])
        #expect(PinGeometry.edges(at: CGPoint(x: 200, y: 100), size: size).isEmpty)
    }
    @Test func testWindowFitsSmallDisplayWithoutDiscardingContent() {
        let result = DS.fittingWindowSize(preferred: DS.windowSize, available: CGSize(width: 1280, height: 680))
        #expect(result.width == 1000)
        #expect(result.height == 640)
    }
    @Test func testReduceMotionDisablesTransition() {
        #expect(DS.motionDuration(reduceMotion: true) == 0)
        #expect(DS.motionDuration(reduceMotion: false) == 0.28)
    }
}
