import Testing
import Foundation
@testable import Settings

final class SettingsTests {
    @Test func olderPreferencesKeepAppearanceWhenCaptureSettingsAreAdded() throws {
        let data=Data(#"{"appearance":"dark","showDockIcon":true,"onboardingCompleted":true}"#.utf8)
        let preferences=try JSONDecoder().decode(Preferences.self,from:data)
        #expect(preferences.appearance == .dark)
        #expect(preferences.showDockIcon)
        #expect(preferences.afterCapture == [.thumbnail])
        #expect(preferences.shortcuts.count == 3)
    }
    @Test func testDefaultsArePrivateAndMenuBarOnly() {
        let preferences = Preferences()
        #expect(!(preferences.showDockIcon))
        #expect(preferences.appearance == .system)
        #expect(!(preferences.onboardingCompleted))
    }

    @Test @MainActor func testChangesSurviveNewStore() throws {
        let suite = "SuperShotTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = SettingsStore(defaults: defaults)
        first.preferences.appearance = .dark
        first.preferences.showDockIcon = true
        let second = SettingsStore(defaults: defaults)
        #expect(second.preferences.appearance == .dark)
        #expect(second.preferences.showDockIcon)
    }

    @Test @MainActor func testCorruptPreferencesArePreservedAndRecover() throws {
        let suite = "SuperShotTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let corrupt = Data("not JSON".utf8)
        defaults.set(corrupt, forKey: SettingsStore.storageKey)
        let store = SettingsStore(defaults: defaults)
        #expect(store.preferences == Preferences())
        #expect(defaults.data(forKey: SettingsStore.recoveryKey) == corrupt)
        #expect(store.recoveryMessage != nil)
    }
}

extension SettingsTests {
    @Test @MainActor func setupIsShownOnlyOnceEvenWhenClosedWithoutPermission() throws {
        let suite = "SuperShotTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = SettingsStore(defaults: defaults)
        #expect(first.claimFirstLaunchSetup(screenAccess: false))
        #expect(!SettingsStore(defaults: defaults).claimFirstLaunchSetup(screenAccess: false))
        defaults.set(Data("invalid".utf8), forKey: SettingsStore.storageKey)
        #expect(!SettingsStore(defaults: defaults).claimFirstLaunchSetup(screenAccess: false))
    }

    @Test @MainActor func existingUsersDoNotGetSetupAgain() throws {
        for granted in [true, false] {
            let suite = "SuperShotTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = SettingsStore(defaults: defaults)
            store.preferences.onboardingCompleted = !granted
            #expect(!store.claimFirstLaunchSetup(screenAccess: granted))
        }
    }

    @Test @MainActor func floatingPreferencesSurviveRelaunchAndOlderSettingsMigrate() throws {
        let old = try JSONDecoder().decode(Preferences.self, from: Data(#"{"appearance":"light"}"#.utf8))
        #expect(old.floating == FloatingPreferences())
        let suite = "SuperShotTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = SettingsStore(defaults: defaults)
        first.preferences.floating.thumbnailCorner = .topLeft
        first.preferences.floating.thumbnailSeconds = 10
        first.preferences.floating.thumbnailWidth = 320
        first.preferences.floating.pinSize = 700
        first.preferences.floating.pinOpacity = 0.5
        first.preferences.floating.pinAllSpaces = false
        first.preferences.floating.pinShadow = false
        #expect(SettingsStore(defaults: defaults).preferences.floating == first.preferences.floating)
        first.preferences.floating.pinOpacity = 2
        #expect(SettingsStore(defaults: defaults).recoveryMessage != nil)
    }

    @Test @MainActor func invalidButWellFormedPreferencesAreRecovered() throws {
        let suite="SuperShotTests.\(UUID().uuidString)",defaults=UserDefaults(suiteName:suite)!
        defer{defaults.removePersistentDomain(forName:suite)}
        var preferences=Preferences();preferences.filenameCounter=Int.max
        let original=try JSONEncoder().encode(preferences);defaults.set(original,forKey:SettingsStore.storageKey)
        let store=SettingsStore(defaults:defaults)
        #expect(store.preferences.filenameCounter == 1)
        #expect(defaults.data(forKey:SettingsStore.recoveryKey) == original)
    }
}

extension SettingsTests {
    @Test @MainActor func storedSettingsMoveToFullQualityOnceAndThenRespectChanges() throws {
        let suite = "SuperShotTests.\(UUID().uuidString)", defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var old = Preferences(); old.quality = 0.92; old.convertToSRGB = true; old.oneX = true
        defaults.set(try JSONEncoder().encode(old), forKey: SettingsStore.storageKey)
        let first = SettingsStore(defaults: defaults)
        #expect(first.preferences.quality == 1 && !first.preferences.convertToSRGB && !first.preferences.oneX)
        first.preferences.quality = 0.5
        #expect(SettingsStore(defaults: defaults).preferences.quality == 0.5)
    }
}

extension SettingsTests {
    @Test @MainActor func captureConvenienceDefaultsAndPersistence() throws {
        let old = try JSONDecoder().decode(Preferences.self, from: Data(#"{"areaAction":"editor","afterCapture":["save","copy"]}"#.utf8))
        #expect(!old.autoCopyScreenshots && !old.captureOnRelease)
        #expect(old.actions(for: .area) == [.editor])
        #expect(old.actions(for: .screen) == [.save, .copy])
        let suite = "SuperShotTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        store.preferences.autoCopyScreenshots = true
        store.preferences.captureOnRelease = true
        let reopened = SettingsStore(defaults: defaults)
        #expect(reopened.preferences.autoCopyScreenshots && reopened.preferences.captureOnRelease)
    }
    @Test func autoCopyAddsToEveryModeWithoutRemovingOtherActions() {
        var preferences = Preferences()
        preferences.autoCopyScreenshots = true
        preferences.areaAction = .editor
        preferences.afterCapture = [.thumbnail, .save]
        preferences.modeActions["window"] = [.pin]
        preferences.modeActions["scrolling"] = []
        #expect(preferences.actions(for: .area) == [.copy, .editor])
        #expect(preferences.actions(for: .screen) == [.copy, .thumbnail, .save])
        #expect(preferences.actions(for: .window) == [.copy, .pin])
        #expect(preferences.actions(for: .scrolling) == [.copy])
        for mode in CaptureActionMode.allCases {
            #expect(preferences.actions(for: mode, override: [.save]) == [.copy, .save])
            #expect(preferences.actions(for: mode, override: [.copy]) == [.copy])
        }
        preferences.autoCopyScreenshots = false
        #expect(preferences.actions(for: .scrolling).isEmpty)
        #expect(preferences.actions(for: .area) == [.editor])
        #expect(preferences.actions(for: .window) == [.pin])
    }
}
