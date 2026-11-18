import AI
import Foundation

/// The CLI owns authentication. Leaving the page cancels the caller's task and stops polling.
@MainActor enum AssistantAccountFlow {
    static func signIn(using service: any AssistantService, interval: Duration = .seconds(2),
                       timeout: Duration = .seconds(300),
                       launch: @MainActor (AssistantSignIn) throws -> Void = AssistantSignInLauncher.launch,
                       waiting: @MainActor () -> Void) async throws -> AssistantAvailability {
        try Task.checkCancellation()
        let continuation = try await service.signIn()
        try Task.checkCancellation()
        try launch(continuation)
        waiting()

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            try await clock.sleep(until: min(deadline, clock.now.advanced(by: interval)))
            try Task.checkCancellation()
            guard clock.now < deadline else { break }
            let state = await service.availability()
            try Task.checkCancellation()
            if case .signedOut = state { continue }
            return state
        }
        throw AssistantError.tool("Sign-in timed out. You can try again.")
    }
}
