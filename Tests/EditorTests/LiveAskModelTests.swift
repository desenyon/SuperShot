import Testing
import Foundation
import CoreGraphics
import ImageIO
import Document
import Export
import AI
@testable import Editor

/// The full Ask path (rendered document → consent → real CLI → streamed reply) against the signed-in Codex.
/// Opt-in only: `SUPERSHOT_LIVE_ASK=1 scripts/test.sh --filter LiveAskModelTests`.
@MainActor struct LiveAskModelTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SUPERSHOT_LIVE_ASK"] == "1"), .timeLimit(.minutes(3)))
    func askModelGetsARealReplyThroughCodex() async throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/previews/thumbnail-light.png")
        let data = try Data(contentsOf: url)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let doc = CaptureDocument(original: data, width: image.width, height: image.height, source: "Fieldnotes — Workspace")
        let model = AskModel(options: AskOptions(provider: .chatgpt, confirmBeforeSending: true, includeRecognizedText: true),
                             factory: { Assistant.service(for: $0) })
        await model.refreshAvailability()
        try #require(model.availability?.isReady == true, "Codex not ready: \(String(describing: model.availability))")
        model.draft = "What is the large headline? Answer in a few words."
        model.send(document: doc)
        #expect(model.awaitingConsent)
        model.confirm(redact: false)
        let deadline = ContinuousClock.now + .seconds(120)
        while (model.isStreaming || model.messages.last?.role != .assistant) && model.error == nil && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        print("Ask error:", model.error ?? "none")
        print("Ask reply:", model.messages.last?.text ?? "")
        #expect(model.error == nil)
        #expect(model.messages.last?.status == .done)
        #expect(model.messages.last?.text.localizedCaseInsensitiveContains("clearer") == true)
        // A quick action through the same live conversation.
        let count = model.messages.count
        model.ask(.named("Explain"), document: doc)
        let second = ContinuousClock.now + .seconds(120)
        while (model.isStreaming || model.messages.count < count + 2) && model.error == nil && ContinuousClock.now < second {
            try await Task.sleep(for: .milliseconds(50))
        }
        print("Explain reply:", model.messages.last?.text.prefix(300) ?? "")
        #expect(model.error == nil && model.messages.last?.status == .done && (model.messages.last?.text.count ?? 0) > 40)
        model.end()
    }
}
