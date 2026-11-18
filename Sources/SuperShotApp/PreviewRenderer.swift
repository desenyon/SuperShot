import AppKit
import SwiftUI
import DesignSystem
import Document
import Render
import Editor
import Settings
import Capture
import Library
import Export

/// Renders the app's main surfaces to PNG files without putting anything on screen.
/// System glass has nothing to sample offscreen, so surfaces use their opaque fallback here.
@MainActor enum PreviewRenderer {
    static func run(output: URL, fixture: URL) {
        DS.rendersOffscreen = true
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        guard let data = try? Data(contentsOf: fixture), let image = DocumentRenderer.decode(data) else {
            FileHandle.standardError.write(Data("Could not read fixture image\n".utf8)); return
        }
        if ProcessInfo.processInfo.environment["PREVIEW_BENCH"] != nil { benchmark(data: data, image: image); return }
        let only = ProcessInfo.processInfo.environment["PREVIEW_ONLY"]
        for dark in [true, false] {
            let suffix = dark ? "dark" : "light"
            for scene in scenes(data: data, image: image) {
                // MARK: Editor customization previews. Scope live theme settings to each synchronous snapshot.
                if scene.name == "editor" {
                    let theme = ThemeState.shared
                    let density = theme.density, chrome = theme.chrome
                    defer { theme.density = density; theme.chrome = chrome }
                    let model = EditorModel(document: document(data, image))
                    model.selected = [model.document.layers[1].id]
                    let compactPalette = EditorChrome(tools: ["select", "text", "arrow", "rectangle", "crop", "image"])
                    var paper = model.document.backdrop
                    paper.fill = .solid; paper.color = .white
                    model.savedPresets = [BackdropPreset(name: "Lagoon", backdrop: model.document.backdrop),
                                          BackdropPreset(name: "Paper", backdrop: paper)]
                    let locked = PinState(image: image)
                    locked.locked = true
                    let customScenes = [
                        Scene(name: "editor-compact", size: scene.size, view: AnyView(EditorView(model: model, chrome: compactPalette))),
                        Scene(name: "editor-solid", size: scene.size, view: AnyView(EditorView(model: model))),
                        Scene(name: "editor-backdrop-presets", size: CGSize(width: 288, height: 200),
                              view: AnyView(BackdropPresets(model: model).fixedSize().modifier(GlassSurface()).padding(DS.sm))),
                        Scene(name: "editor-export-options", size: CGSize(width: 200, height: 380),
                              view: AnyView(ExportOptions(model: model, dismiss: {}).modifier(GlassSurface()).padding(DS.sm))),
                        Scene(name: "pin-opacity", size: CGSize(width: 200, height: 96),
                              view: AnyView(PinOpacityControl(state: PinState(image: image, opacity: 0.75)).modifier(GlassSurface()).padding(DS.sm))),
                        Scene(name: "pin-locked", size: CGSize(width: 420, height: 270), view: AnyView(PinView(state: locked)))
                    ]
                    for variant in customScenes where only.map({ variant.name.contains($0) }) ?? true {
                        theme.density = variant.name == "editor-compact" ? .compact : density
                        theme.chrome = variant.name == "editor-solid" ? .solid : chrome
                        snapshot(variant.view, size: variant.size, dark: dark,
                                 to: output.appendingPathComponent("\(variant.name)-\(suffix).png"))
                    }
                }
                // End editor customization previews.
                guard only.map({ scene.name.contains($0) }) ?? true else { continue }
                snapshot(scene.view, size: scene.size, dark: dark, to: output.appendingPathComponent("\(scene.name)-\(suffix).png"))
            }
        }
    }

    struct Scene { let name: String; let size: CGSize; let view: AnyView }

    static func document(_ data: Data, _ image: CGImage) -> CaptureDocument {
        var doc = CaptureDocument(original: data, width: image.width, height: image.height, scale: 2, source: "Fieldnotes")
        doc.backdrop.fill = .gradient
        doc.backdrop.stops = DS.gradients[0].hex.map { hex in
            let c = DS.components(hex); return RGBA(red: c.red, green: c.green, blue: c.blue)
        }
        doc.backdrop.angle = 45; doc.backdrop.padding = 96; doc.backdrop.radius = 20; doc.backdrop.shadow = 0.45
        var arrow = Layer(kind: .arrow, rect: CGRect(x: 330, y: 640, width: 260, height: 90), points: [CGPoint(x: 590, y: 640), CGPoint(x: 330, y: 705)], stroke: 6)
        arrow.arrowHead = "filled"; arrow.arrowBend = 0.18
        let box = Layer(kind: .rectangle, rect: CGRect(x: 60, y: 668, width: 244, height: 82), stroke: 5)
        let one = Layer(kind: .counter, rect: CGRect(x: 610, y: 600, width: 56, height: 56), text: "1", fontSize: 30)
        var note = Layer(kind: .text, rect: CGRect(x: 690, y: 608, width: 280, height: 40), color: .white, text: "Saves the project", fontSize: 30)
        note.textBackground = .black
        doc.layers = [box, arrow, one, note]
        return doc
    }

    static func scenes(data: Data, image: CGImage) -> [Scene] {
        var list: [Scene] = []
        let editor = EditorModel(document: document(data, image))
        editor.tool = "arrow"; editor.selected = [editor.document.layers[1].id]
        list.append(Scene(name: "editor", size: DS.editorSize, view: AnyView(EditorView(model: editor))))

        let panels = EditorModel(document: document(data, image))
        panels.tool = "select"; panels.inspector = "intelligence"
        panels.commit { $0.backdrop.fill = .solid; $0.backdrop.color = RGBA(red: 0.11, green: 0.11, blue: 0.13) }
        list.append(Scene(name: "editor-smart", size: DS.editorSize, view: AnyView(EditorView(model: panels))))

        var plain = document(data, image); plain.backdrop = Backdrop(); plain.layers = []
        let bare = EditorModel(document: plain)
        bare.tool = "select"; bare.inspector = "layers"
        list.append(Scene(name: "editor-plain", size: DS.editorMinimum, view: AnyView(EditorView(model: bare))))
        list.append(contentsOf: appScenes(image: image))
        return list
    }

    static func snapshot(_ view: AnyView, size: CGSize, dark: Bool, to url: URL) {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height).environment(\.colorScheme, dark ? .dark : .light))
        host.sizingOptions = []
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.appearance = appearance; window.contentView = host
        host.layoutSubtreeIfNeeded()
        // Let asynchronous image rendering and view tasks settle.
        RunLoop.main.run(until: Date().addingTimeInterval(0.9))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.contentView = nil
    }
}

extension PreviewRenderer {
    static func appScenes(image: CGImage) -> [Scene] {
        var list: [Scene] = []
        let suite = "SuperShot.preview.\(UUID().uuidString)"
        let store = SettingsStore(defaults: UserDefaults(suiteName: suite)!)
        for section in SettingsView.Section.allCases {
            let name = section == .floating ? "floating" : section.rawValue.lowercased()
            list.append(Scene(name: "settings-\(name)", size: DS.settingsSize,
                              view: AnyView(SettingsView(store: store, hasScreenAccess: true, initialSection: section, openPrivacy: {}))))
            list.append(Scene(name: "settings-narrow-\(name)", size: CGSize(width: 680, height: 1600),
                              view: AnyView(SettingsView(store: store, hasScreenAccess: true, initialSection: section, openPrivacy: {}))))
            list.append(Scene(name: "settings-accessible-\(name)", size: DS.settingsSize,
                              view: AnyView(SettingsView(store: store, hasScreenAccess: true, initialSection: section, openPrivacy: {})
                                .settingsAccessibilityPreview())))
        }
        for section in [SettingsView.Section.capture, .output, .shortcuts, .floating] {
            list.append(Scene(name: "settings-full-\(section == .floating ? "floating" : section.rawValue.lowercased())", size: CGSize(width: DS.settingsSize.width, height: 1600),
                              view: AnyView(SettingsView(store: store, hasScreenAccess: true, initialSection: section, openPrivacy: {}))))
        }
        list.append(Scene(name: "settings-small", size: CGSize(width: 680, height: 440),
                          view: AnyView(SettingsView(store: store, hasScreenAccess: true, initialSection: .floating, openPrivacy: {}))))
        let quickStore = SettingsStore(defaults: UserDefaults(suiteName: suite + ".quick")!)
        quickStore.preferences.autoCopyScreenshots = true
        quickStore.preferences.captureOnRelease = true
        quickStore.preferences.modeActions = ["screen": [.copy, .save], "window": [.thumbnail, .pin], "scrolling": []]
        let longStore = SettingsStore(defaults: UserDefaults(suiteName: suite + ".long")!)
        longStore.preferences.saveFolder = "/Volumes/Shared Work/Design Reviews/Release Candidates/November 2026/Retina screenshots and annotated reference images"
        longStore.preferences.backdropPresets = [BackdropPreset(name: "Product documentation with generous margins and a custom desktop background", backdrop: Backdrop())]
        longStore.shortcutError = "That shortcut is already used by another SuperShot action. Choose a different combination."
        for section in [SettingsView.Section.output, .shortcuts] {
            list.append(Scene(name: "settings-long-\(section.rawValue.lowercased())", size: CGSize(width: 680, height: 1600),
                              view: AnyView(SettingsView(store: longStore, hasScreenAccess: true, initialSection: section, openPrivacy: {}))))
        }
        list.append(Scene(name: "settings-quick-capture", size: DS.settingsSize,
                          view: AnyView(SettingsView(store: quickStore, hasScreenAccess: true, initialSection: .capture, openPrivacy: {}))))
        list.append(Scene(name: "settings-small-capture", size: CGSize(width: 680, height: 440),
                          view: AnyView(SettingsView(store: store, hasScreenAccess: true, initialSection: .capture, openPrivacy: {}))))
        for (name, granted) in [("welcome", true), ("welcome-permission", false)] {
            let permission = ScreenPermission(check: { granted }, request: { granted })
            list.append(Scene(name: name, size: DS.welcomeSize,
                              view: AnyView(WelcomeView(settings: store, permission: permission, capture: { _ in }, openSettings: {}, openPrivacy: {}, finish: {}))))
        }
        let capture = CapturedImage(image: image, scale: 2, source: "Fieldnotes")
        list.append(Scene(name: "thumbnail", size: DS.thumbnailSize,
                          view: AnyView(ThumbnailView(capture: capture, open: {}, copy: {}, save: {}, pin: {}, dismiss: {}))))
        list.append(Scene(name: "countdown", size: CGSize(width: 220, height: 236), view: AnyView(CountdownView(state: CountdownState(seconds: 3)))))
        list.append(Scene(name: "scrolling", size: CGSize(width: 300, height: 320), view: AnyView(ScrollPanel(model: ScrollModel(image: image)))))
        list.append(Scene(name: "pin", size: CGSize(width: 420, height: 270), view: AnyView(PinView(state: PinState(image: image)))))

        let activePin = PinState(image: image); activePin.hovering = true
        list.append(Scene(name: "pin-controls", size: CGSize(width: 420, height: 270), view: AnyView(PinView(state: activePin))))
        list.append(Scene(name: "pin-narrow", size: CGSize(width: 100, height: 300), view: AnyView(PinView(state: activePin))))
        list.append(Scene(name: "settings-permission", size: DS.settingsSize,
                          view: AnyView(SettingsView(store: store, hasScreenAccess: false, initialSection: .privacy, openPrivacy: {}))))

        let screen = CGSize(width: 1100, height: 707)
        let shot = CapturedImage(image: image, scale: 1400 / 1100, source: "Display")
        list.append(Scene(name: "overlay-aiming", size: screen, view: AnyView(Hosted(view: SelectionOverlay.previewView(size: screen, capture: shot, selection: .zero, pointer: CGPoint(x: 420, y: 300))))))
        list.append(Scene(name: "overlay-quick", size: screen, view: AnyView(Hosted(view: SelectionOverlay.previewView(size: screen, capture: shot, selection: .zero, pointer: CGPoint(x: 420, y: 300), captureOnRelease: true)))))
        list.append(Scene(name: "overlay-area", size: screen, view: AnyView(Hosted(view: SelectionOverlay.previewView(size: screen, capture: shot, selection: CGRect(x: 40, y: 150, width: 680, height: 330), pointer: CGPoint(x: 720, y: 480))))))
        let target = CaptureWindow(id: 1, title: "Fieldnotes", frame: CGRect(x: 760, y: 190, width: 260, height: 260))
        list.append(Scene(name: "overlay-window", size: screen, view: AnyView(Hosted(view: SelectionOverlay.previewView(size: screen, capture: shot, windows: [target], selection: target.frame, pointer: CGPoint(x: 880, y: 300))))))

        // A throwaway library with real thumbnails, so the grid is reviewed with content.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        let history = HistoryStore(folder: folder)
        let model = HistoryModel(store: history)
        if let data = try? ImageExport.encode(image) {
            var entries: [HistoryEntry] = []
            for (index, name) in ["Fieldnotes", "Safari", "Xcode", "Figma", "Notes", "Terminal"].enumerated() {
                var doc = CaptureDocument(original: data, width: image.width, height: image.height, scale: 2, source: name, date: Date().addingTimeInterval(-Double(index) * 5400))
                if index % 2 == 0 {
                    doc.backdrop.fill = .gradient; doc.backdrop.padding = 110; doc.backdrop.angle = 45
                    doc.backdrop.stops = DS.gradients[index % DS.gradients.count].hex.map { let c = DS.components($0); return RGBA(red: c.red, green: c.green, blue: c.blue) }
                }
                let size = DocumentRenderer.layout(doc).size
                if let preview = try? DocumentRenderer.render(doc, scale: 480 / max(size.width, size.height)), let png = try? ImageExport.encode(preview) {
                    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try? png.write(to: history.thumbnailURL(doc.id))
                }
                entries.append(HistoryEntry(id: doc.id, date: doc.date, title: name, width: Int(size.width), height: Int(size.height), text: ""))
            }
            model.entries = entries
        }
        list.append(Scene(name: "library", size: DS.previewSize, view: AnyView(HistoryView(model: model))))
        list.append(Scene(name: "library-empty", size: DS.previewSize, view: AnyView(HistoryView(model: HistoryModel(store: HistoryStore(folder: folder.appendingPathComponent("empty")))))))
        return list
    }
}

extension PreviewRenderer {
    /// Times the work behind one editor frame on a 5K-wide capture: the raster refresh and the live overlay paint.
    static func benchmark(data: Data, image: CGImage) {
        let width = 5120, height = 2880
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let big = context.makeImage(), let png = try? ImageExport.encode(big) else { return }
        var doc = document(png, big)
        doc.layers = (0..<40).map { index in
            Layer(kind: index % 2 == 0 ? .arrow : .rectangle, rect: CGRect(x: 100 + index * 110, y: 200 + index * 50, width: 400, height: 240),
                  points: [CGPoint(x: 100 + index * 110, y: 200 + index * 50), CGPoint(x: 500 + index * 110, y: 440 + index * 50)], stroke: 8)
        }
        func time(_ label: String, runs: Int = 12, _ work: () -> Void) {
            work()
            let clock = ContinuousClock(), elapsed = clock.measure { for _ in 0..<runs { work() } }
            let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
            print(String(format: "%@: %.1f ms", label, ms / Double(runs)))
        }
        let longest = Double(max(DocumentRenderer.layout(doc).size.width, DocumentRenderer.layout(doc).size.height))
        time("Raster refresh while dragging a control (1280 px)") { _ = try? DocumentRenderer.render(doc, scale: 1280 / longest) }
        time("Raster refresh at rest (2200 px)") { _ = try? DocumentRenderer.render(doc, scale: 2200 / longest) }
        time("Full-resolution export render", runs: 3) { _ = try? DocumentRenderer.render(doc) }
        let overlay = CGContext(data: nil, width: 2560, height: 1640, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        overlay.scaleBy(x: 0.4, y: 0.4)
        time("Live overlay paint, 1 selected layer", runs: 200) { DocumentRenderer.drawLive([doc.layers[0]], document: doc, scale: 0.4, context: overlay) }
        time("Live overlay paint, 40 selected layers", runs: 100) { DocumentRenderer.drawLive(doc.layers, document: doc, scale: 0.4, context: overlay) }
    }
}

private struct Hosted: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
