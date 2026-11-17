import Carbon
import Foundation

public struct Shortcut: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    public var keyLabel: String = ""
    public init(keyCode: UInt32, modifiers: UInt32, keyLabel: String = "") { self.keyCode = keyCode; self.modifiers = modifiers; self.keyLabel = keyLabel }
    public var display: String {
        (modifiers & UInt32(controlKey) != 0 ? "⌃" : "") +
        (modifiers & UInt32(optionKey) != 0 ? "⌥" : "") +
        (modifiers & UInt32(shiftKey) != 0 ? "⇧" : "") +
        (modifiers & UInt32(cmdKey) != 0 ? "⌘" : "") + keyLabel.uppercased()
    }
    public static let defaults: [String: Shortcut] = [
        "screen": Shortcut(keyCode:20,modifiers:UInt32(cmdKey | shiftKey | controlKey),keyLabel:"3"),
        "area": Shortcut(keyCode:21,modifiers:UInt32(cmdKey | shiftKey | controlKey),keyLabel:"4"),
        "window": Shortcut(keyCode:23,modifiers:UInt32(cmdKey | shiftKey | controlKey),keyLabel:"5")
    ]
    public static func hasConflict(_ shortcuts: [Shortcut]) -> Bool {
        Set(shortcuts.map { "\($0.keyCode):\($0.modifiers)" }).count != shortcuts.count
    }
}
@MainActor public final class GlobalHotkeys {
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var actions: [UInt32: () -> Void] = [:]
    public init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            let owner = Unmanaged<GlobalHotkeys>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { owner.actions[id.id]?() }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    public func register(id: UInt32, shortcut: Shortcut, action: @escaping () -> Void) throws {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature:0x53534854,id:id), GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &ref)
        guard status == noErr, let ref else { throw NSError(domain:"SuperShot.Hotkey",code:Int(status),userInfo:[NSLocalizedDescriptionKey:"A screenshot shortcut is already in use (\(status))."]) }
        refs.append(ref); actions[id] = action
    }
    public func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }; refs.removeAll(); actions.removeAll()
    }
}

public extension Shortcut {
    static let actions: [(id:String,title:String)] = [
        ("screen","Capture screen"),("area","Capture area"),("window","Capture window"),
        ("all","Capture all displays"),("previous","Capture previous area"),("scrolling","Scrolling capture"),
        ("timed","Timed area capture"),("text","Recognize text"),("code","Scan QR / barcode"),
        ("last","Open last capture"),("history","Open capture library"),("pin","Pin from clipboard"),
        ("icons","Hide desktop icons in captures")
    ]
    static let unassigned = Shortcut(keyCode:0,modifiers:0,keyLabel:"Record shortcut")
    static let editorDefaults: [String:String] = ["select":"v","crop":"c","arrow":"a","rectangle":"r","oval":"o","line":"l","text":"t","drawing":"d","highlighter":"h","counter":"n","blur":"b","pixelate":"x","spotlight":"s","magnifier":"m","erase":"e","ruler":"u","picker":"i"]
    static var systemScreenshotPreset: [String:Shortcut] {
        ["screen":Shortcut(keyCode:20,modifiers:UInt32(cmdKey|shiftKey),keyLabel:"3"),"area":Shortcut(keyCode:21,modifiers:UInt32(cmdKey|shiftKey),keyLabel:"4"),"window":Shortcut(keyCode:23,modifiers:UInt32(cmdKey|shiftKey),keyLabel:"5")]
    }
}
public struct ShortcutProfile: Codable, Sendable {
    public var version=1
    public var global:[String:Shortcut]
    public var editor:[String:String]
    public init(global:[String:Shortcut],editor:[String:String]) {self.global=global;self.editor=editor}
    public func validate() throws {
        let allowed=Set(Shortcut.actions.map(\.id))
        let effective=Shortcut.editorDefaults.merging(editor){_,new in new}
        guard version == 1,global.keys.allSatisfy({allowed.contains($0) || ($0.hasPrefix("preset.") && UUID(uuidString:String($0.dropFirst(7))) != nil)}),!Shortcut.hasConflict(Array(global.values)),
              global.values.allSatisfy({$0.keyCode<128 && $0.modifiers & UInt32(cmdKey|controlKey|optionKey) != 0}),
              Set(editor.keys).isSubset(of:Set(Shortcut.editorDefaults.keys)),
              editor.values.allSatisfy({$0.count == 1 && $0.unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains)}),
              Set(effective.values.map{$0.lowercased()}).count == effective.count else {
            throw NSError(domain:"SuperShot.Shortcuts",code:1,userInfo:[NSLocalizedDescriptionKey:"This shortcut profile has conflicts, unsupported keys, or an unknown version."])
        }
    }
}
