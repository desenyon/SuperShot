import SwiftUI
import AppKit

/// SuperShot's icon set: Phosphor, drawn from embedded SVG so it renders identically on screen,
/// offscreen, in menus, and in AppKit views. Call sites may pass a Phosphor name ("push-pin")
/// or one of the SF Symbol names the app used before ("pin"); both resolve here.
public enum IconWeight: String, Sendable { case regular, fill, bold }

public enum Icons {
    /// SF Symbol names used by earlier code, mapped to their Phosphor replacements.
    public static let legacy: [String: String] = [
        "text.viewfinder": "scan", "qrcode.viewfinder": "qr-code", "qrcode": "qr-code",
        "doc.on.doc": "copy", "xmark": "x", "xmark.circle.fill": "x-circle", "trash": "trash",
        "square.and.arrow.down": "download-simple", "pencil.tip.crop.circle": "pencil-simple",
        "viewfinder": "frame-corners", "camera.viewfinder": "camera", "square.3.layers.3d": "stack",
        "photo.stack": "images", "magnifyingglass": "magnifying-glass", "plus.magnifyingglass": "magnifying-glass-plus",
        "lock.shield": "shield-check", "checkmark.shield": "shield-check", "exclamationmark.shield": "shield-warning",
        "lock": "lock-simple", "lock.fill": "lock-simple", "lock.open": "lock-simple-open", "pin": "push-pin",
        "pin.fill": "push-pin", "checkmark.circle.fill": "check-circle", "checkmark": "check",
        "checkmark.square.fill": "check-square", "arrow.up.right": "arrow-up-right", "textformat": "text-t",
        "text.bubble": "chat-text", "text.alignleft": "text-align-left", "square.stack": "stack-simple",
        "square.grid.3x3": "grid-nine", "square.fill": "square", "square": "square", "square.and.arrow.up": "export",
        "square.and.arrow.down.on.square": "tray-arrow-down", "square.3.layers.3d.top.filled": "selection-foreground",
        "square.3.layers.3d.bottom.filled": "selection-background", "ruler": "ruler", "rotate.right": "arrow-clockwise",
        "rectangle.on.rectangle": "app-window", "macwindow": "app-window", "rectangle.inset.filled": "selection-all",
        "rectangle.dashed": "selection", "rectangle": "rectangle", "plus": "plus", "minus": "minus",
        "photo.on.rectangle.angled": "images-square", "photo.badge.plus": "image-square", "photo": "image",
        "person.crop.rectangle": "user-square", "pencil.tip": "pen-nib", "line.diagonal": "line-segment",
        "info.circle": "info", "highlighter": "highlighter", "hand.draw": "scribble", "gearshape": "gear-six",
        "flashlight.on.fill": "flashlight", "eye": "eye", "eye.slash": "eye-slash", "exclamationmark.triangle": "warning",
        "eraser": "eraser", "ellipsis": "dots-three", "drop.halffull": "drop-half", "doc.on.clipboard": "clipboard-text",
        "cursorarrow": "cursor", "cursorarrow.rays": "cursor-click", "circle.lefthalf.filled": "circle-half",
        "circle": "circle", "chevron.left.forwardslash.chevron.right": "code", "chevron.down": "caret-down",
        "chevron.up": "caret-up", "chevron.right": "caret-right", "chevron.left": "caret-left",
        "chevron.up.chevron.down": "caret-up-down", "character.textbox": "textbox", "character.cursor.ibeam": "cursor-text",
        "arrow.uturn.backward": "arrow-u-up-left", "arrow.uturn.forward": "arrow-u-up-right",
        "arrow.up.left.and.arrow.down.right": "arrows-out-simple", "arrow.down.right.and.arrow.up.left": "arrows-in-simple",
        "arrow.up.and.down.text.horizontal": "scroll", "arrow.counterclockwise": "arrow-counter-clockwise",
        "a.square": "translate", "1.circle": "number-circle-one", "timer": "timer", "crop": "crop",
        "keyboard": "keyboard", "command": "command", "display": "monitor", "folder": "folder", "power": "power",
        "eyedropper": "eyedropper", "photo.badge.arrow.down": "file-image", "sparkles": "magic-wand", "wand.and.stars": "magic-wand",
        "tablecells": "table", "tag": "tag", "clock": "clock", "hand.raised": "hand", "paintpalette": "palette",
        "slider.horizontal.3": "sliders-horizontal", "arrow.up": "arrow-up", "stop.fill": "stop",
        "bubble.left.and.text.bubble.right": "chats-circle", "scope": "crosshair-simple", "bounding.box": "bounding-box"
    ]

    static func phosphorName(_ name: String) -> String? {
        let candidate = legacy[name] ?? name
        return table(.regular)[candidate] == nil ? nil : candidate
    }

    /// Whether `name` resolves to an embedded icon.
    public static func contains(_ name: String) -> Bool { phosphorName(name) != nil }

    nonisolated(unsafe) private static var tables: [IconWeight: [String: String]] = [:]
    private static let lock = NSLock()
    static func table(_ weight: IconWeight) -> [String: String] {
        lock.lock(); defer { lock.unlock() }
        if let table = tables[weight] { return table }
        let source: String = switch weight { case .regular: PhosphorData.regular; case .fill: PhosphorData.fill; case .bold: PhosphorData.bold }
        var table: [String: String] = [:]
        for line in source.split(separator: "\n") {
            guard let tab = line.firstIndex(of: "\t") else { continue }
            table[String(line[..<tab])] = String(line[line.index(after: tab)...])
        }
        tables[weight] = table
        return table
    }

    nonisolated(unsafe) private static var cache: [String: NSImage] = [:]
    /// A template image of `name` at `size` points. Falls back to the SF Symbol for unmapped names.
    public static func image(_ name: String, weight: IconWeight = .regular, size: CGFloat = 16) -> NSImage {
        let key = "\(name)|\(weight.rawValue)|\(size)"
        lock.lock(); if let hit = cache[key] { lock.unlock(); return hit }; lock.unlock()
        let image: NSImage
        if let resolved = phosphorName(name), let body = table(weight)[resolved] ?? table(.regular)[resolved],
           let data = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 256 256\" width=\"\(size)\" height=\"\(size)\" fill=\"#000\">\(body)</svg>".data(using: .utf8),
           let svg = NSImage(data: data) {
            image = svg
        } else {
            image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: size * 0.86, weight: weight == .bold ? .semibold : .regular)) ?? NSImage(size: NSSize(width: size, height: size))
        }
        image.size = NSSize(width: size, height: size)
        image.isTemplate = true
        lock.lock(); cache[key] = image; lock.unlock()
        return image
    }
}

public extension Icons {
    /// A non-template copy filled with `color`, for drawing directly in AppKit views.
    static func tinted(_ name: String, color: NSColor, weight: IconWeight = .regular, size: CGFloat = 16) -> NSImage {
        let template = image(name, weight: weight, size: size)
        return NSImage(size: template.size, flipped: false) { rect in
            template.draw(in: rect)
            color.set(); rect.fill(using: .sourceAtop)
            return true
        }
    }
}

/// An icon from SuperShot's set, tinted by the current foreground style.
public struct Icon: View {
    private let name: String
    private let weight: IconWeight
    private let size: CGFloat
    public init(_ name: String, weight: IconWeight = .regular, size: CGFloat = DS.icon) {
        self.name = name; self.weight = weight; self.size = size
    }
    public var body: some View {
        Image(nsImage: Icons.image(name, weight: weight, size: size))
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
