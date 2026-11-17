import AppIntents
import AppKit

/// Xcode extracts App Intents metadata when opening this package as an app target.
/// The Command Line Tools bundle also supports supershot:// URLs for Shortcuts.
struct CaptureAreaIntent: AppIntent {
    static var title: LocalizedStringResource { "Capture an Area" }
    static var description: IntentDescription { "Select an area of the screen with SuperShot." }
    static var openAppWhenRun: Bool { true }
    @MainActor func perform() async throws -> some IntentResult {
        (NSApp.delegate as? AppDelegate)?.handleURL(URL(string:"supershot://capture?mode=area")!)
        return .result()
    }
}
struct CaptureScreenIntent: AppIntent {
    static var title: LocalizedStringResource { "Capture the Screen" }
    static var openAppWhenRun: Bool { true }
    @MainActor func perform() async throws -> some IntentResult {
        (NSApp.delegate as? AppDelegate)?.handleURL(URL(string:"supershot://capture?mode=screen")!)
        return .result()
    }
}
struct RecognizeTextIntent: AppIntent {
    static var title: LocalizedStringResource { "Copy Text from the Screen" }
    static var openAppWhenRun: Bool { true }
    @MainActor func perform() async throws -> some IntentResult {
        (NSApp.delegate as? AppDelegate)?.handleURL(URL(string:"supershot://capture?mode=text")!)
        return .result()
    }
}
