import Testing
import AppKit
@testable import Hotkeys
struct HotkeysTests {
    @Test @MainActor func neutralRecorderKeepsCaptureAndCancellationBehavior() throws {
        let button = RecorderButton()
        button.neutral = true
        var changes: [Shortcut] = []
        var states: [Bool] = []
        button.changed = { changes.append($0) }
        button.recordingChanged = { states.append($0) }
        button.performClick(nil)
        #expect(button.recording)
        #expect(button.focusRingType == .none)
        let key = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [.command, .shift], timestamp: 0, windowNumber: 0,
            context: nil, characters: "6", charactersIgnoringModifiers: "6", isARepeat: false, keyCode: 22))
        button.keyDown(with: key) // Delivered only to this detached control; never posted to macOS.
        #expect(changes.count == 1)
        #expect(changes.first?.keyCode == 22)
        #expect(!button.recording)
        button.performClick(nil)
        button.cancelRecording()
        #expect(!button.recording)
        #expect(changes.count == 1)
        #expect(states == [true, false, true, false])
    }

    @Test @MainActor func closingRecorderWindowCancelsRecording() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:200,height:100),styleMask:.titled,backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false
        let button=RecorderButton()
        window.contentView=button
        var recording=false
        button.recordingChanged = { recording=$0 }
        button.performClick(nil)
        #expect(recording)
        window.close()
        #expect(!recording)
    }
    @Test func detectsDuplicateButAllowsDifferentModifiers() {
        let a = Shortcut(keyCode:20,modifiers:1)
        #expect(Shortcut.hasConflict([a,a]))
        #expect(!Shortcut.hasConflict([a,Shortcut(keyCode:20,modifiers:2)]))
    }
}
