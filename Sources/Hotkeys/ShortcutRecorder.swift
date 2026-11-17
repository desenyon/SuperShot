import AppKit
import SwiftUI
import Carbon
import DesignSystem

public struct ShortcutRecorder: NSViewRepresentable {
    public var neutral: Bool
    public let shortcut: Shortcut
    public let recordingChanged: (Bool) -> Void
    public let changed: (Shortcut) -> Void
    public init(neutral: Bool = false, shortcut: Shortcut, recordingChanged: @escaping (Bool) -> Void, changed: @escaping (Shortcut) -> Void) { self.neutral=neutral; self.shortcut=shortcut; self.recordingChanged=recordingChanged; self.changed=changed }
    public func makeNSView(context: Context) -> RecorderButton { RecorderButton() }
    public static func dismantleNSView(_ button: RecorderButton, coordinator: ()) { button.cancelRecording() }
    public func updateNSView(_ button: RecorderButton, context: Context) {
        button.shortcut=shortcut; button.changed=changed; button.recordingChanged=recordingChanged
        button.neutral = neutral
        if !button.recording { button.title=button.label }
    }
}
@MainActor public final class RecorderButton: NSButton {
    var neutral = false { didSet { updateStyle() } }
    var shortcut=Shortcut(keyCode:0,modifiers:0)
    var changed: ((Shortcut) -> Void)?
    var recordingChanged: ((Bool) -> Void)?
    var recording=false { didSet {
        recordingChanged?(recording)
        updateStyle()
    } }
    /// Unassigned shortcuts invite recording instead of showing an empty key.
    var label: String {
        if shortcut.modifiers == 0 { return neutral ? "Record…" : "Record" }
        return neutral ? shortcut.display.map(String.init).joined(separator: " ") : shortcut.display
    }
    override public var acceptsFirstResponder: Bool { true }
    init() {
        super.init(frame:.zero)
        isBordered = false; font = .systemFont(ofSize: 12, weight: .medium)
        wantsLayer = true; layer?.cornerRadius = 7; layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        layer?.borderWidth = 1; layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        target=self; action=#selector(beginRecording)
        setAccessibilityLabel("Record keyboard shortcut")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func updateStyle() {
        let focused = window?.firstResponder === self
        focusRingType = neutral ? .none : .default
        layer?.cornerRadius = neutral ? DS.Preferences.controlRadius : 7
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(neutral ? 0.045 : 0.08).cgColor
            layer?.borderColor = ((recording || (neutral && focused)) ? (neutral ? DS.Preferences.nsFocus : DS.nsAccent) : NSColor.labelColor.withAlphaComponent(0.18)).cgColor
        }
        layer?.borderWidth = (recording || (neutral && focused)) ? DS.Preferences.focusWidth : DS.Preferences.hairline
        setAccessibilityValue(recording ? "Recording; press a shortcut or Escape to cancel" : label)
    }
    override public func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateStyle() }
    override public func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateStyle() }
    override public func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        DispatchQueue.main.async { [weak self] in self?.updateStyle() }
        return result
    }
    override public func viewWillMove(toWindow newWindow: NSWindow?) {
        cancelRecording()
        NotificationCenter.default.removeObserver(self)
        if let newWindow {
            NotificationCenter.default.addObserver(self, selector:#selector(cancelRecording), name:NSWindow.willCloseNotification, object:newWindow)
            NotificationCenter.default.addObserver(self, selector:#selector(cancelRecording), name:NSWindow.didResignKeyNotification, object:newWindow)
        }
        super.viewWillMove(toWindow:newWindow)
    }
    @objc func cancelRecording() {
        guard recording else { return }
        recording=false; title=label
    }
    @objc private func beginRecording() {
        recording=true; title="Type shortcut…"; window?.makeFirstResponder(self)
    }
    override public func resignFirstResponder() -> Bool {
        recording=false; title=label
        let result = super.resignFirstResponder()
        // During this callback the window still identifies us as its first responder.
        DispatchQueue.main.async { [weak self] in self?.updateStyle() }
        return result
    }
    override public func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with:event) }
        keyDown(with:event); return true
    }
    override public func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with:event); return }
        if event.keyCode == 53 { recording=false; title=label; return }
        let flags=event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command,.control,.option]).isEmpty else { NSSound.beep(); return }
        var modifiers: UInt32=0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        let value=Shortcut(keyCode:UInt32(event.keyCode),modifiers:modifiers,keyLabel:event.charactersIgnoringModifiers ?? "?")
        recording=false; changed?(value); title=label
    }
}
