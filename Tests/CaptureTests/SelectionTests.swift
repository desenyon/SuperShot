import Testing
import Foundation
@testable import Capture
struct SelectionTests {
    @Test func reversedDragClampsToScreen() {
        #expect(SelectionGeometry.rectangle(from: CGPoint(x:120,y:90), to: CGPoint(x:-20,y:10), bounds: CGRect(x:0,y:0,width:100,height:100)) == CGRect(x:0,y:10,width:100,height:80))
    }
    @Test func retinaCropPreservesTopLeftAndClamps() {
        #expect(SelectionGeometry.pixels(selection: CGRect(x:10,y:20,width:100,height:50), viewSize: CGSize(width:200,height:100), imageSize: CGSize(width:400,height:200)) == CGRect(x:20,y:40,width:200,height:100))
    }
    @Test func zeroViewDoesNotDivideByZero() {
        #expect(SelectionGeometry.pixels(selection:.zero,viewSize:.zero,imageSize:CGSize(width:100,height:100)) == .zero)
    }
}

// Direct events on a detached view: no NSWindow, screen capture, or global input.
import AppKit

@MainActor private func overlayFixture(release: Bool, complete: @escaping (CGRect?, CGWindowID?, OverlayAction) -> Void) throws -> NSView {
    let context = try #require(CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let capture = CapturedImage(image: try #require(context.makeImage()), scale: 2, source: "Test")
    let view = SelectionView(frame: CGRect(x: 0, y: 0, width: 400, height: 300), capture: capture, windows: nil,
                             snappingWindows: [], screenOrigin: .zero, completion: complete)
    view.captureOnRelease = release
    return view
}
@MainActor private func mouse(_ type: NSEvent.EventType, _ x: Double, _ y: Double) throws -> NSEvent {
    try #require(NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: 300 - y), modifierFlags: [.option], timestamp: 0,
                                    windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
}
@MainActor private func key(_ code: UInt16, characters: String = "") throws -> NSEvent {
    try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                  context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
}

extension SelectionTests {
    @Test @MainActor func defaultAreaWaitsForEnterAndCompletesOnlyOnce() throws {
        var results: [CGRect?] = []
        let view = try overlayFixture(release: false) { rect, _, _ in results.append(rect) }
        view.mouseDown(with: try mouse(.leftMouseDown, 20, 30))
        view.mouseDragged(with: try mouse(.leftMouseDragged, 100, 90))
        view.mouseUp(with: try mouse(.leftMouseUp, 120, 110))
        #expect(results.isEmpty)
        view.keyDown(with: try key(36))
        view.keyDown(with: try key(36))
        #expect(results.count == 1)
        #expect(results.first! == CGRect(x: 20, y: 30, width: 100, height: 80))
    }
    @Test @MainActor func releaseCapturesFinalPositionAndPreservesRetinaPixels() throws {
        var results: [CGRect?] = []
        let view = try overlayFixture(release: true) { rect, _, _ in results.append(rect) }
        view.mouseDown(with: try mouse(.leftMouseDown, 120, 110))
        view.mouseDragged(with: try mouse(.leftMouseDragged, 40, 40))
        view.mouseUp(with: try mouse(.leftMouseUp, 20, 30))
        view.mouseUp(with: try mouse(.leftMouseUp, 20, 30))
        view.keyDown(with: try key(36))
        #expect(results.count == 1)
        let rect = try #require(results.first!)
        #expect(rect == CGRect(x: 20, y: 30, width: 100, height: 80))
        #expect(SelectionGeometry.pixels(selection: rect, viewSize: CGSize(width: 400, height: 300), imageSize: CGSize(width: 800, height: 600)) == CGRect(x: 40, y: 60, width: 200, height: 160))
    }
    @Test @MainActor func releaseIgnoresClicksAndZeroAreaDrags() throws {
        var calls = 0
        let view = try overlayFixture(release: true) { _, _, _ in calls += 1 }
        view.mouseDown(with: try mouse(.leftMouseDown, 20, 30))
        view.mouseUp(with: try mouse(.leftMouseUp, 20, 30))
        view.mouseDown(with: try mouse(.leftMouseDown, 20, 30))
        view.mouseDragged(with: try mouse(.leftMouseDragged, 20, 90))
        view.mouseUp(with: try mouse(.leftMouseUp, 20, 90))
        #expect(calls == 0)
    }
    @Test @MainActor func escapeDuringDragCancelsExactlyOnce() throws {
        var results: [CGRect?] = []
        let view = try overlayFixture(release: true) { rect, _, _ in results.append(rect) }
        view.mouseDown(with: try mouse(.leftMouseDown, 20, 30))
        view.mouseDragged(with: try mouse(.leftMouseDragged, 100, 90))
        view.keyDown(with: try key(53))
        view.mouseUp(with: try mouse(.leftMouseUp, 120, 110))
        #expect(results.count == 1 && results[0] == nil)
    }
    @Test @MainActor func typedSelectionCanStillBeResizedBeforeEnterInQuickMode() throws {
        var results: [CGRect?] = []
        let view = try overlayFixture(release: true) { rect, _, _ in results.append(rect) }
        view.keyDown(with: try key(0, characters: "200x100"))
        view.keyDown(with: try key(36))
        #expect(results.isEmpty)
        view.mouseDown(with: try mouse(.leftMouseDown, 100, 50))
        view.mouseDragged(with: try mouse(.leftMouseDragged, 120, 80))
        view.mouseUp(with: try mouse(.leftMouseUp, 140, 90))
        #expect(results.isEmpty)
        view.keyDown(with: try key(36))
        #expect(results.count == 1)
        #expect(results[0] == CGRect(x: 0, y: 0, width: 140, height: 90))
    }
}
