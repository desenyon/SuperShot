import AppIntents
import AppKit

enum CaptureURLMode: String, AppEnum {
    case area, screen, all, window, previous, scrolling, text, code, disposable, webpage

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Capture mode"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .area: "Area", .screen: "Current display", .all: "All displays", .window: "Window",
        .previous: "Previous area", .scrolling: "Scrolling", .text: "Recognize text",
        .code: "Scan code", .disposable: "Disposable area", .webpage: "Webpage"
    ]
}

enum CaptureURLCommand: Equatable {
    case capture(CaptureURLMode), timed(Int), history, recent, record, recordings

    init?(_ url: URL) {
        guard url.scheme?.lowercased() == "supershot",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        switch components.host?.lowercased() {
        case "history": self = .history
        case "recent": self = .recent
        case "record": self = .record
        case "recordings": self = .recordings
        case "capture":
            let query = Dictionary(components.queryItems?.map { ($0.name, $0.value ?? "") } ?? [],
                                   uniquingKeysWith: { _, latest in latest })
            guard let mode = CaptureURLMode(rawValue: query["mode"]?.lowercased() ?? "area") else { return nil }
            if let delay = query["delay"] {
                guard mode == .area, let seconds = Int(delay), [3, 5, 10].contains(seconds) else { return nil }
                self = .timed(seconds)
            } else { self = .capture(mode) }
        default: return nil
        }
    }
}

/// Xcode extracts App Intents metadata when opening this package as an app target.
/// The Command Line Tools bundle also supports supershot:// URLs for Shortcuts.
struct CaptureWithSuperShotIntent: AppIntent {
    static var title: LocalizedStringResource { "Capture with SuperShot" }
    static var openAppWhenRun: Bool { true }
    @Parameter(title: "Capture mode", default: .area) var mode: CaptureURLMode

    @MainActor func perform() async throws -> some IntentResult {
        (NSApp.delegate as? AppDelegate)?.performCaptureCommand(.capture(mode))
        return .result()
    }
}

struct RecordWithSuperShotIntent: AppIntent {
    static var title: LocalizedStringResource { "Set Up a Screen Recording" }
    static var openAppWhenRun: Bool { true }

    @MainActor func perform() async throws -> some IntentResult {
        (NSApp.delegate as? AppDelegate)?.performCaptureCommand(.record)
        return .result()
    }
}

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
