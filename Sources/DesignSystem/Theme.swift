import SwiftUI
import AppKit
import Observation

public extension DS {
    /// The accent the user picked. None of these is violet or purple.
    enum AccentChoice: String, Codable, CaseIterable, Sendable, Identifiable {
        case blue, teal, graphite, tangerine
        public var id: String { rawValue }
        public var title: String { rawValue.capitalized }
    }
    /// Spacing scale for floating chrome.
    enum Density: String, Codable, CaseIterable, Sendable, Identifiable {
        case compact, regular
        public var id: String { rawValue }
        public var title: String { rawValue.capitalized }
    }
    /// Floating chrome material.
    enum Chrome: String, Codable, CaseIterable, Sendable, Identifiable {
        case glass, solid
        public var id: String { rawValue }
        public var title: String { rawValue.capitalized }
    }
}

/// Live interface choices. `DS.accent` and friends read from here, so SwiftUI views that use
/// them update when the user changes a choice; AppKit views redraw on `DS.themeDidChange`.
@MainActor @Observable public final class ThemeState {
    public static let shared = ThemeState()
    public var accent: DS.AccentChoice = .blue { didSet { if accent != oldValue { notify() } } }
    public var density: DS.Density = .regular { didSet { if density != oldValue { notify() } } }
    public var chrome: DS.Chrome = .glass { didSet { if chrome != oldValue { notify() } } }
    private func notify() { NotificationCenter.default.post(name: DS.themeDidChange, object: nil) }
}

public extension DS {
    static let themeDidChange = Notification.Name("SuperShot.themeDidChange")
}
