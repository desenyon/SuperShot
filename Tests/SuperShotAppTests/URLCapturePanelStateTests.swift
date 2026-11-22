import Capture
import CoreGraphics
import Testing
@testable import SuperShotApp

@MainActor struct URLCapturePanelStateTests {
    @Test func missingAddressAndInvalidDimensionsKeepTheFormReady() {
        let state = URLCapturePanelState(resolveBrowser: { "Chrome" }, render: { _ in
            Issue.record("Invalid requests should never reach the browser")
            throw URLCaptureError.pageUnavailable
        })
        #expect(state.capture { _ in } == nil)
        #expect(state.errorMessage == "Enter the page URL.")
        #expect(!state.isCapturing)

        state.address = "example.org"
        state.breakpoint = .custom
        state.customWidth = "128"
        state.customHeight = "0"
        #expect(state.capture { _ in } == nil)
        #expect(state.error == .invalidSize)
        state.customHeight = " 800 "
        #expect(state.error == nil)
        #expect(state.dimensions.height == 800)
    }

    @Test func missingBrowserCanBeRecoveredFromTheOpenForm() async throws {
        var installed: String?
        let image = try image()
        let state = URLCapturePanelState(resolveBrowser: { installed }, render: { _ in image })
        state.address = "example.org"
        #expect(state.capture { _ in } == nil)
        #expect(state.error == .browserMissing)
        #expect(state.shouldRetry)

        installed = "Chrome"
        var results: [String] = []
        let retry = try #require(state.capture { results.append($0.source) })
        await retry.value
        #expect(state.browserName == "Chrome")
        #expect(results == ["example.org"])
        #expect(state.error == nil)
        #expect(!state.isCapturing)
    }

    @Test func failureAllowsRetryAndPreservesCaptureOptions() async throws {
        let image = try image()
        var requests: [URLCaptureRequest] = []
        let state = URLCapturePanelState(resolveBrowser: { "Chrome" }, render: { request in
            requests.append(request)
            if requests.count == 1 { throw URLCaptureError.navigationFailed }
            return image
        })
        state.address = "example.org/path"
        state.breakpoint = .phone
        state.appearance = .dark
        state.scope = .viewport
        var completions = 0

        let failed = try #require(state.capture { _ in completions += 1 })
        await failed.value
        #expect(state.error == .navigationFailed)
        #expect(state.shouldRetry)
        #expect(completions == 0)

        let retry = try #require(state.capture { _ in completions += 1 })
        await retry.value
        #expect(completions == 1)
        #expect(state.error == nil)
        #expect(!state.isCapturing)
        #expect(requests.count == 2)
        for request in requests {
            #expect(request.url.absoluteString == "https://example.org/path")
            #expect(request.width == 390 && request.height == 844)
            #expect(request.appearance == .dark && request.scope == .viewport)
        }
    }

    @Test func cancelledResultCannotCloseAReopenedPanelOrInterruptItsRetry() async throws {
        let image = try image()
        let gate = CaptureGate()
        let state = URLCapturePanelState(resolveBrowser: { "Chrome" }, render: { _ in await gate.render() })
        state.address = "example.org"
        var results: [String] = []
        let first = try #require(state.capture { _ in results.append("cancelled") })
        await gate.waitForRenders(1)
        #expect(state.isCapturing)
        #expect(state.capture { _ in results.append("duplicate") } == nil)
        state.cancel()
        #expect(!state.isCapturing)

        let retry = try #require(state.capture { _ in results.append("retry") })
        await gate.waitForRenders(2)
        gate.finish(0, with: image)
        await first.value
        #expect(state.isCapturing)
        #expect(results.isEmpty)
        gate.finish(1, with: image)
        await retry.value
        #expect(results == ["retry"])
        #expect(!state.isCapturing)
    }

    @Test func windowSizeFitsTheAvailableDisplay() {
        let normal = URLCaptureWindowController.fittingSize(available: CGSize(width: 1600, height: 900))
        #expect(normal == URLCaptureWindowController.panelSize)
        let compact = URLCaptureWindowController.fittingSize(available: CGSize(width: 420, height: 360))
        #expect(compact.width < 420 && compact.height < 360)
        #expect(compact.width > 340 && compact.height > 280)
    }

    private func image() throws -> CapturedImage {
        let context = try #require(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
                                             bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return CapturedImage(image: try #require(context.makeImage()), scale: 1, source: "example.org")
    }
}

@MainActor private final class CaptureGate {
    private var pending: [CheckedContinuation<CapturedImage, Never>] = []
    private var waiter: (count: Int, continuation: CheckedContinuation<Void, Never>)?

    func render() async -> CapturedImage {
        await withCheckedContinuation { continuation in
            pending.append(continuation)
            if let waiter, pending.count >= waiter.count {
                self.waiter = nil
                waiter.continuation.resume()
            }
        }
    }

    func waitForRenders(_ count: Int) async {
        guard pending.count < count else { return }
        await withCheckedContinuation { waiter = (count, $0) }
    }

    func finish(_ index: Int, with image: CapturedImage) {
        pending[index].resume(returning: image)
    }
}
