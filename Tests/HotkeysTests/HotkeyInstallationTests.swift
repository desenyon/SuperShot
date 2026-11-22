import Foundation
import Hotkeys
import Testing

struct HotkeyInstallationTests {
    @Test func systemConflictPreservesOtherBindingsAtLaunch() {
        let area = Shortcut(keyCode: 21, modifiers: 1)
        let window = Shortcut(keyCode: 23, modifiers: 1)
        let result = HotkeyInstallation.register(actions: ["area", "window"], requested: ["area": area, "window": window], previous: [:]) { _, shortcut in
            if shortcut == area { throw CocoaError(.userCancelled) }
        }
        #expect(result.installed == ["window": window])
        #expect(result.preferences == ["area": area, "window": window])
        #expect(result.failures.map(\.action) == ["area"])
    }

    @Test func rejectedChangeFallsBackWithoutTakingAnotherActionsNewKey() {
        let area = Shortcut(keyCode: 21, modifiers: 1)
        let window = Shortcut(keyCode: 23, modifiers: 1)
        let rejected = Shortcut(keyCode: 20, modifiers: 1)
        var taken: [Shortcut] = []
        let result = HotkeyInstallation.register(actions: ["area", "window"], requested: ["area": rejected, "window": area],
                                                 previous: ["area": area, "window": window]) { _, shortcut in
            if shortcut == rejected || taken.contains(shortcut) { throw CocoaError(.userCancelled) }
            taken.append(shortcut)
        }
        #expect(result.installed == ["window": area])
        #expect(result.failures.map(\.action) == ["area"])
    }
}
