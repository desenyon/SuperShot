import SwiftUI
import AppKit
import Document
import Render
import DesignSystem
import Export

/// The editor window: an edge-to-edge canvas with floating glass chrome.
public struct EditorView: View {
    @Bindable var model: EditorModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var textFocused: Bool

    public init(model: EditorModel) { self.model = model }

    public var body: some View {
        ZStack {
            canvasBackground.ignoresSafeArea()
            EditorCanvas(model: model).ignoresSafeArea()
            if let point = model.textViewPoint, model.textPoint != nil { inlineTextField(at: point) }
            // One container lets the system sample the canvas once for all floating surfaces.
            GlassEffectContainer(spacing: 0) { chrome }.ignoresSafeArea()
        }
        .animation(DS.spring(reduceMotion: reduceMotion), value: model.inspector)
        .animation(DS.spring(reduceMotion: reduceMotion), value: model.showBackdrop)
        .animation(DS.quick(reduceMotion: reduceMotion), value: model.tool)
        .animation(DS.quick(reduceMotion: reduceMotion), value: model.selected)
        .animation(DS.quick(reduceMotion: reduceMotion), value: model.status)
        .alert("SuperShot", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK") { model.message = nil }
        } message: { Text(model.message ?? "") }
        .task(id: model.status) {
            // Status messages are transient confirmations.
            guard !model.status.isEmpty, !model.busy else { return }
            do { try await Task.sleep(for: .seconds(2.4)) } catch { return }
            if !model.busy { model.status = "" }
        }
    }

    private var canvasBackground: some View {
        ZStack {
            scheme == .dark ? DS.midnight : DS.paper
            // A faint pool of light behind the image keeps the canvas from looking flat.
            RadialGradient(colors: [scheme == .dark ? Color.white.opacity(0.055) : Color.white.opacity(0.9), .clear],
                           center: .center, startRadius: 0, endRadius: 720)
        }
    }

    // MARK: Chrome

    private var chrome: some View {
        VStack(spacing: DS.sm) {
            HStack(spacing: DS.sm) {
                // An invisible twin of the switcher keeps the palette centered without ever overlapping it.
                panelSwitcher.hidden().accessibilityHidden(true)
                Spacer(minLength: 0)
                ToolPalette(model: model)
                Spacer(minLength: 0)
                panelSwitcher
            }
            ToolOptionsBar(model: model)
            HStack(alignment: .top, spacing: 0) {
                if model.showBackdrop {
                    BackdropPanel(model: model).transition(.move(edge: .leading).combined(with: .opacity))
                }
                Spacer(minLength: 0)
                if !model.inspector.isEmpty {
                    SidePanel(model: model).transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxHeight: .infinity)
            ZStack(alignment: .bottom) {
                HStack(alignment: .bottom) { documentBar; Spacer(); exportBar }
                VStack(spacing: DS.sm) {
                    if model.busy || !model.status.isEmpty { toast.transition(.opacity.combined(with: .scale(scale: 0.96))) }
                    zoomBar
                }
            }
        }
        .padding(DS.edge)
    }

    private var panelSwitcher: some View {
        EditorPanelSwitcher(model: model)
    }

    private var documentBar: some View {
        HStack(spacing: 2) {
            IconButton("rectangle.inset.filled", label: "Backdrop", selected: model.showBackdrop) { model.showBackdrop.toggle() }
            divider
            IconButton("arrow.uturn.backward", label: "Undo · ⌘Z") { model.undo() }.disabled(!model.canUndo)
            IconButton("arrow.uturn.forward", label: "Redo · ⇧⌘Z") { model.redo() }.disabled(!model.canRedo)
            divider
            Text(model.document.source).font(DS.caption).lineLimit(1).frame(maxWidth: 140, alignment: .leading).padding(.leading, DS.xs)
            DimensionTag(model: model).padding(.trailing, DS.xs)
        }
        .padding(6).frame(height: DS.barHeight).modifier(GlassSurface(radius: DS.pill))
    }
    private var zoomBar: some View {
        HStack(spacing: 2) {
            IconButton("minus", label: "Zoom out · ⌘−") { model.zoom(by: 0.8) }
            Menu {
                Button("Fit to window  ⌘0") { model.zoomToFit() }
                Divider()
                ForEach([0.5, 1, 2, 4, 8], id: \.self) { value in
                    Button("\(Int(value * 100))%") { model.zoom = value; model.pan = .zero }
                }
            } label: {
                Text(model.zoom == 0 ? "Fit" : "\(Int((model.zoom * 100).rounded()))%").font(DS.mono).frame(width: 44)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Zoom")
            IconButton("plus", label: "Zoom in · ⌘+") { model.zoom(by: 1.25) }
        }
        .padding(6).frame(height: DS.barHeight).modifier(GlassSurface(radius: DS.pill))
    }

    private var exportBar: some View {
        HStack(spacing: DS.xs) {
            HStack(spacing: DS.xs) {
                Icon("hand.draw", size: 14)
                Text("Drag").font(DS.caption)
            }
            .foregroundStyle(.secondary).padding(.horizontal, DS.sm).frame(height: DS.toolButton)
            .overlay(Capsule().strokeBorder(DS.hairline(scheme), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            .contentShape(Capsule())
            .onDrag { dragProvider() }
            .help("Drag the finished image into another app").accessibilityLabel("Drag image")
            IconButton("pin", label: "Pin to screen") { model.export(pin: true) }.disabled(model.pinAction == nil || model.busy)
            ShareButton(model: model).frame(width: DS.toolButton, height: DS.toolButton)
            IconButton("square.and.arrow.down.on.square", label: "Save editable project · ⇧⌘S") { model.saveProject() }
            divider
            Button { model.export(copy: true) } label: { Label { Text("Copy") } icon: { Icon("doc.on.doc", size: 16) } }
                .buttonStyle(QuietButtonStyle()).disabled(model.busy).help("Copy image · ⌘C")
            HStack(spacing: 0) {
                Button { model.export() } label: { Text("Save").font(DS.emphasis).padding(.leading, DS.lg).padding(.trailing, DS.sm).frame(height: DS.toolButton) }
                    .buttonStyle(.plain).help("Save image · ⌘S")
                Rectangle().fill(.white.opacity(0.25)).frame(width: 1, height: 14)
                Menu {
                    ForEach(ImageExport.formats) { format in
                        Button { model.format = format.id } label: {
                            if model.format == format.id { Label(format.name, systemImage: "checkmark") } else { Text(format.name) }
                        }
                    }
                    Divider()
                    Picker("Resolution", selection: $model.outputMultiplier) {
                        Text("Original size").tag(1.0); Text("2× resample").tag(2.0); Text("4× resample").tag(4.0)
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(ImageExport.formats.first { $0.id == model.format }?.name ?? "PNG").font(DS.mono)
                        Icon("chevron.down", weight: .bold, size: 10)
                    }.foregroundStyle(.white).padding(.leading, DS.sm).padding(.trailing, DS.md).frame(height: DS.toolButton).contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Format and resolution")
            }
            .foregroundStyle(.white).background(DS.accent, in: Capsule())
            .opacity(model.busy ? 0.5 : 1).disabled(model.busy)
        }
        .padding(6).frame(height: DS.barHeight).modifier(GlassSurface(radius: DS.pill))
    }

    private var toast: some View {
        HStack(spacing: DS.sm) {
            if model.busy { ProgressView().controlSize(.small) }
            else { Icon("checkmark.circle.fill").foregroundStyle(DS.success) }
            Text(model.status.isEmpty ? "Working…" : model.status).font(DS.caption).lineLimit(1)
        }
        .padding(.horizontal, DS.md).frame(height: 30).modifier(GlassSurface(radius: DS.pill))
    }

    private var divider: some View {
        Rectangle().fill(DS.hairline(scheme)).frame(width: 1, height: 18).padding(.horizontal, DS.xs)
    }

    private func inlineTextField(at point: CGPoint) -> some View {
        TextField("Type, then press Return", text: $model.textInput)
            .textFieldStyle(.plain).font(DS.body)
            .focused($textFocused)
            .onSubmit { model.addText() }
            .onExitCommand { model.cancelText() }
            .padding(.horizontal, DS.md).frame(width: 240, height: 34)
            .modifier(GlassSurface(radius: DS.smallRadius))
            .overlay(RoundedRectangle(cornerRadius: DS.smallRadius, style: .continuous).strokeBorder(DS.accent, lineWidth: 1.5))
            .position(x: point.x + 120, y: point.y + 17)
            .onAppear { textFocused = true }
    }

    private func dragProvider() -> NSItemProvider {
        let provider = NSItemProvider(), doc = model.document, multiplier = model.outputMultiplier
        provider.registerDataRepresentation(forTypeIdentifier: "public.png", visibility: .all) { completion in
            Task.detached {
                do { completion(try ImageExport.encode(DocumentRenderer.render(doc, scale: multiplier)), nil) }
                catch { completion(nil, error) }
            }
            return nil
        }
        return provider
    }
}

/// Reads the live document on its own, so dragging a control re-evaluates this label and not the whole editor.
private struct DimensionTag: View {
    let model: EditorModel
    var body: some View {
        let size = DocumentRenderer.layout(model.current).size
        Tag("\(Int(size.width)) × \(Int(size.height))")
    }
}

// MARK: - Tool palette

struct ToolPalette: View {
    @Bindable var model: EditorModel
    @Environment(\.colorScheme) private var scheme

    private static let groups: [[String]] = [
        ["select", "crop"],
        ["arrow", "rectangle", "oval", "line"],
        ["text", "counter", "drawing", "highlighter"],
        ["blur", "pixelate", "erase", "spotlight", "magnifier"],
        ["ruler", "picker"]
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(Self.groups.enumerated()), id: \.offset) { index, group in
                if index > 0 { separator }
                ForEach(group, id: \.self) { id in toolButton(id) }
            }
            separator
            IconButton("photo.badge.plus", label: "Paste image · ⌘V") { model.pasteImage() }
        }
        .padding(6).frame(height: DS.barHeight).modifier(GlassSurface(radius: DS.pill))
    }
    private var separator: some View {
        Rectangle().fill(DS.hairline(scheme)).frame(width: 1, height: 18).padding(.horizontal, DS.xs)
    }
    private func toolButton(_ id: String) -> some View {
        let info = Self.info(id)
        let key = (model.toolShortcuts[id] ?? info.shortcut).uppercased()
        return IconButton(info.symbol, label: "\(info.title) · \(key)", selected: model.tool == id) {
            if model.textPoint != nil { model.addText() }
            if id != "select" { model.selected = [] }
            model.tool = id
        }
    }
    static func info(_ id: String) -> (title: String, symbol: String, shortcut: String) {
        switch id {
        case "select": ("Select", "cursorarrow", "v")
        case "crop": ("Crop", "crop", "c")
        case "picker": ("Color picker", "eyedropper", "i")
        default:
            if let tool = ToolRegistry.tool(id) { (tool.title, tool.symbol, tool.shortcut) } else { (id.capitalized, "questionmark", "") }
        }
    }
}

// MARK: - Window

@MainActor public final class EditorWindowController: NSWindowController {
    public let model: EditorModel
    public init(document: CaptureDocument) {
        model = EditorModel(document: document)
        let size = DS.fittingWindowSize(preferred: DS.editorSize, available: NSScreen.main?.visibleFrame.size ?? DS.editorSize)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "\(document.source) — SuperShot"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = DS.editorMinimum
        // An empty unified toolbar gives a taller title bar, which centers the window buttons on the tool palette.
        let toolbar = NSToolbar(identifier: "editor")
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        let host = NSHostingView(rootView: EditorView(model: model))
        host.sizingOptions = []
        window.contentView = host
        window.setContentSize(size)
        window.center()
        super.init(window: window)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    public func present() { NSApp.activate(ignoringOtherApps: true); showWindow(nil); window?.makeKeyAndOrderFront(nil) }
}

extension RGBA {
    init(hex: UInt32) {
        let c = DS.components(hex)
        self.init(red: c.red, green: c.green, blue: c.blue)
    }
}
