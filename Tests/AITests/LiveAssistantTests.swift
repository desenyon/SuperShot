import Testing
import Foundation
import CoreGraphics
import ImageIO
@testable import AI

/// Real turns against the signed-in CLIs. Opt-in only: `SUPERSHOT_LIVE_ASK=1 scripts/test.sh --filter LiveAssistantTests`.
/// Uses the user's plan, so it never runs in the default or background suites.
struct LiveAssistantTests {
    static let enabled = ProcessInfo.processInfo.environment["SUPERSHOT_LIVE_ASK"] == "1"

    private func fixture() throws -> CGImage {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/previews/thumbnail-light.png")
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func converse(_ provider: AssistantProvider) async throws {
        let service = Assistant.service(for: provider)
        let state = await service.availability()
        try #require(state.isReady, "\(provider.title) is not ready: \(state)")
        let chat = try await service.startConversation(AssistantContext(image: try fixture(), recognizedText: "A clearer kind of work.", appName: "Fieldnotes"), model: nil)
        defer { Task { await chat.close() } }
        var reply = "", done = false
        for try await event in chat.send("In one short sentence: what is the large headline in this screenshot?", attachments: []) {
            if case .delta(let text) = event { reply += text }
            if case .done = event { done = true }
        }
        print("\(provider.title) reply 1:", reply)
        #expect(done && reply.localizedCaseInsensitiveContains("clearer"))
        var followUp = ""
        for try await event in chat.send("Reply with only the word that follows \"kind of\" in that headline.", attachments: []) {
            if case .delta(let text) = event { followUp += text }
        }
        print("\(provider.title) reply 2:", followUp)
        #expect(followUp.localizedCaseInsensitiveContains("work"))
    }

    @Test(.enabled(if: LiveAssistantTests.enabled), .timeLimit(.minutes(3)))
    func chatGPTThroughCodexAnswersAndFollowsUp() async throws { try await converse(.chatgpt) }

    @Test(.enabled(if: LiveAssistantTests.enabled && Assistant.availableProviders.contains(.claude) &&
        ProcessInfo.processInfo.environment["SUPERSHOT_LIVE_CLAUDE"] == "1"), .timeLimit(.minutes(3)))
    func claudeThroughClaudeCodeAnswersAndFollowsUp() async throws { try await converse(.claude) }
}
