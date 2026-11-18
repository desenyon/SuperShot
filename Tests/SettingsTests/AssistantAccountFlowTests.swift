import AI
import Foundation
import Testing
@testable import Settings

@MainActor struct AssistantAccountFlowTests {
    @Test func signInLaunchesTheReturnedContinuationThenPollsForTheAccount() async throws {
        let service = PreviewAssistantService()
        var events: [String] = []
        let state = try await AssistantAccountFlow.signIn(using: service, interval: .zero, launch: { continuation in
            #expect(continuation == .openURL(URL(string: "https://example.com/sign-in")!))
            events.append("launch")
        }, waiting: { events.append("waiting") })
        #expect(state == service.state)
        #expect(events == ["launch", "waiting"])
    }

    @Test func signedOutToolTimesOutAndCancelledPollingStops() async {
        let service = PreviewAssistantService(state: .signedOut(toolVersion: "1", toolPath: "/fixture"))
        await #expect(throws: AssistantError.self) {
            _ = try await AssistantAccountFlow.signIn(using: service, timeout: .zero, launch: { _ in }, waiting: {})
        }
        let task = Task {
            try await AssistantAccountFlow.signIn(using: service, launch: { _ in }, waiting: {
                withUnsafeCurrentTask { $0?.cancel() }
            })
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }
}
