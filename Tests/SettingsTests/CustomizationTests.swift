import AppKit
import Foundation
import Testing
@testable import Settings

struct CustomizationTests {
    @Test func legacyAndPartialPayloadsPreserveDefaults() throws {
        let old = try JSONDecoder().decode(Preferences.self, from: Data(#"{"appearance":"dark"}"#.utf8))
        #expect(old.appearance == .dark)
        #expect(old.customization == CustomizationPreferences())
        #expect(old.assistant == AssistantPreferences())

        let data = Data(#"{"customization":{"density":"compact"},"assistant":{"keepConversations":false}}"#.utf8)
        var look = CustomizationPreferences()
        look.density = .compact
        var ask = AssistantPreferences()
        ask.keepConversations = false
        let partial = try JSONDecoder().decode(Preferences.self, from: data)
        #expect(partial.customization == look)
        #expect(partial.assistant == ask)
    }

    @Test func decodedListsKeepOnlyUniqueKnownIDsAndPinCaptureFirst() throws {
        let data = Data(#"{"editorTools":["bad","ruler","crop","ruler"],"overlayActions":["pin","capture","bad","capture"],"thumbnailActions":["delete","ask","bad","delete"]}"#.utf8)
        let decoded = try JSONDecoder().decode(CustomizationPreferences.self, from: data)
        #expect(decoded.editorTools == ["ruler", "crop"])
        #expect(decoded.overlayActions == ["capture", "pin"])
        #expect(decoded.thumbnailActions == ["delete", "ask"])
        #expect(CustomizationList.overlay.normalized([]) == ["capture"])
        #expect(CustomizationList.thumbnail.normalized([]).isEmpty)
    }

    @Test func visibilityAndReorderPreserveToolbarInvariants() {
        let list = CustomizationList.overlay
        let initial = ["capture", "copy", "ask", "save"]
        let moved = list.moving("save", to: "copy", in: initial)
        #expect(moved == ["capture", "save", "copy", "ask"])
        #expect(list.moving("save", to: "ask", in: moved) == initial)
        #expect(list.moving("capture", to: "ask", in: initial) == initial)
        #expect(list.moving("copy", to: "capture", in: initial) == initial)
        #expect(list.moving("absent", to: "ask", in: initial) == initial)
        #expect(list.setting("capture", visible: false, in: initial) == initial)
        #expect(list.setting("invalid", visible: true, in: initial) == initial)
        #expect(list.setting("ask", visible: true, in: initial) == initial)
        let hidden = list.setting("ask", visible: false, in: initial)
        #expect(hidden == ["capture", "copy", "save"])
        #expect(list.setting("ask", visible: true, in: hidden) == ["capture", "copy", "save", "ask"])
        #expect(movingItem("Summarize", to: "Explain", in: ["Explain", "Summarize"]) == ["Summarize", "Explain"])
    }

    @Test func configuredToolbarsAndAssistantRoundTrip() throws {
        var p = Preferences()
        p.customization.accent = .tangerine
        p.customization.density = .compact
        p.customization.chrome = .solid
        p.customization.editorTools = ["select", "arrow"]
        p.customization.overlayActions = ["capture", "ask"]
        p.customization.overlayLabels = false
        p.customization.thumbnailActions = []
        p.assistant.provider = "claude"
        p.assistant.model = "sonnet"
        p.assistant.confirmBeforeSending = false
        p.assistant.includeRecognizedText = false
        p.assistant.redactBeforeSending = true
        p.assistant.keepConversations = false
        p.assistant.suggestions = ["Describe the interface"]
        let reopened = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(p))
        #expect(reopened == p)
    }

    @Test @MainActor func copyInstallHintUsesSuppliedPasteboard() {
        let board = NSPasteboard(name: .init("SuperShot.SettingsTests.\(UUID())"))
        defer { board.releaseGlobally() }
        AssistantInstallHint.copy("npm i -g @openai/codex", to: board)
        #expect(board.string(forType: .string) == "npm i -g @openai/codex")
    }
}

extension CustomizationTests {
    @Test func duplicateAndBlankSuggestionChipsMigrate() throws {
        let data = Data(#"{"suggestions":["Explain","  Explain ","","Summarize"]}"#.utf8)
        let preferences = try JSONDecoder().decode(AssistantPreferences.self, from: data)
        #expect(preferences.suggestions == ["Explain", "Summarize"])
    }
}

struct SuggestionMigrationTests {
    @Test func untouchedOldDefaultsBecomeTheFourQuickActions() throws {
        let old = #"{"suggestions":["Explain this","Summarize","What should I do next?","Write alt text"]}"#
        #expect(try JSONDecoder().decode(AssistantPreferences.self, from: Data(old.utf8)).suggestions == ["Solve", "Explain", "Suggest", "Improve"])
        let custom = #"{"suggestions":["Summarize","Translate"]}"#
        #expect(try JSONDecoder().decode(AssistantPreferences.self, from: Data(custom.utf8)).suggestions == ["Summarize", "Translate"])
        #expect(AssistantPreferences().suggestions == ["Solve", "Explain", "Suggest", "Improve"])
    }
}

struct PinUnlockPreferenceTests {
    @Test func olderFloatingPreferencesKeepTheirValuesAndDefaultToOption() throws {
        let saved = #"{"thumbnailCorner":"topLeft","thumbnailSeconds":10,"thumbnailWidth":300,"pinSize":600,"pinOpacity":0.8,"pinAllSpaces":false,"pinShadow":false}"#
        let floating = try JSONDecoder().decode(FloatingPreferences.self, from: Data(saved.utf8))
        #expect(floating.thumbnailCorner == .topLeft && floating.pinSize == 600 && !floating.pinShadow)
        #expect(floating.pinUnlockKey == .option)
        let unknown = try JSONDecoder().decode(FloatingPreferences.self, from: Data(#"{"pinUnlockKey":"hyper"}"#.utf8))
        #expect(unknown.pinUnlockKey == .option)
        var changed = FloatingPreferences(); changed.pinUnlockKey = .command
        let round = try JSONDecoder().decode(FloatingPreferences.self, from: JSONEncoder().encode(changed))
        #expect(round.pinUnlockKey == .command)
        #expect(PinUnlockKey.allCases.map(\.symbol) == ["⌥", "⌘", "⌃", "⇧"])
    }
}
