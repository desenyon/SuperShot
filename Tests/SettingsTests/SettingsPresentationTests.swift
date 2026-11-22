import Testing
import AppKit
import DesignSystem
import Hotkeys
@testable import Settings

struct SettingsPresentationTests {
    @Test @MainActor func navigationIncludesEverySectionAndSearchMatchesAllTerms() {
        let all = SettingsSidebar.matches("")
        #expect(all.count == SettingsView.Section.allCases.count)
        #expect(Set(all) == Set(SettingsView.Section.allCases))
        #expect(Set(SettingsSidebar.quickPages.map(\.section)).count == SettingsSidebar.quickPages.count)
        #expect(SettingsSidebar.quickPages.allSatisfy { all.contains($0.section) })
        #expect(SettingsSidebar.matches("  TiFf   QUALITY  ") == [.output])
        #expect(SettingsSidebar.matches("camera video") == [.capture])
        #expect(SettingsSidebar.matches("pin unlock") == [.floating])
        #expect(SettingsSidebar.matches("review links") == [.privacy])
        #expect(SettingsSidebar.matches("no such control").isEmpty)
    }

    @Test @MainActor func macOSScreenshotPresetPreservesOtherBindingsAndRejectsConflicts() throws {
        let webpage = Shortcut(keyCode: 12, modifiers: 256, keyLabel: "Q")
        let existing = Shortcut.defaults.merging(["webpage": webpage]) { _, new in new }
        let updated = try #require(SettingsView.shortcutsApplyingSystemScreenshotPreset(to: existing))
        #expect(updated["webpage"] == webpage)
        for (id, shortcut) in Shortcut.systemScreenshotPreset {
            #expect(updated[id] == shortcut)
        }
        var conflicting = existing
        conflicting["stopRecording"] = Shortcut.systemScreenshotPreset["area"]
        #expect(SettingsView.shortcutsApplyingSystemScreenshotPreset(to: conflicting) == nil)
    }

    @Test @MainActor func qualityControlReflectsWhichExportsCanUseIt() {
        #expect(SettingsView.qualityLabel(fileFormat: "public.png", clipboardFormat: "public.tiff") == nil)
        #expect(SettingsView.qualityLabel(fileFormat: "com.adobe.pdf", clipboardFormat: "public.png") == nil)
        #expect(SettingsView.qualityLabel(fileFormat: "public.heic", clipboardFormat: "public.png") == "File quality")
        #expect(SettingsView.qualityLabel(fileFormat: "public.png", clipboardFormat: "public.jpeg") == "Clipboard quality")
        #expect(SettingsView.qualityLabel(fileFormat: "public.avif", clipboardFormat: "org.webmproject.webp") == "File and clipboard quality")
    }

    @Test @MainActor func selectionTintColorsHaveComponentsAcrossAppearances() throws {
        let light = try #require(NSAppearance(named: .aqua))
        let dark = try #require(NSAppearance(named: .darkAqua))
        for choice in DS.AccentChoice.allCases {
            var lightTint = SettingsView.selectionTintColor(choice)
            var darkTint = lightTint
            light.performAsCurrentDrawingAppearance { lightTint = SettingsView.selectionTintColor(choice) }
            dark.performAsCurrentDrawingAppearance { darkTint = SettingsView.selectionTintColor(choice) }
            #expect(lightTint == darkTint)
            #expect([lightTint.red, lightTint.green, lightTint.blue].allSatisfy { (0...1).contains($0) })
        }
    }
}
