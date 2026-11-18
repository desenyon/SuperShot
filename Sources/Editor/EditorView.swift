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
    @LocalState private var choosingFormat = false

    private let configuration: EditorChrome
    public init(model: EditorModel, chrome: EditorChrome = EditorChrome()) {
        self.model = model
        self.configuration = chrome
    }

    public var body: some View {
        ZStack {
            canvasBackground.ignoresSafeArea()
            EditorCanvas(model: model).ignoresSafeArea()
            if let point = model.textViewPoint, model.textPoint != nil { inlineTextField(at: point) }
            // One container lets the system sample the canvas once for all floating surfaces.
            GlassEffectContainer(spacing: 0) { chrome }.ignoresSafeArea()
        }
        .animation(DS.Motion.panel(reduceMotion), value: model.inspector)
        .animation(DS.Motion.panel(reduceMotion), value: model.showBackdrop)
        .animation(DS.Motion.snappy(reduceMotion), value: model.tool)
        .animation(DS.Motion.snappy(reduceMotion), value: model.selected)
        .animation(DS.Motion.arrive(reduceMotion), value: model.status)
        .alert("SuperShot", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK") { model.message = nil }
        } message: { Text(model.message ?? "") }
        .task(id: model.exportFeedback) {
            guard model.exportFeedback != nil else { return }
            do { try await Task.sleep(for: .seconds(2.4)) } catch { return }
            model.exportFeedback = nil
        }
        .task(id: model.busy ? nil : model.status) {
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
            RadialGradient(colors: [DS.canvasGlow(scheme), .clear],
                           center: .center, startRadius: 0, endRadius: DS.canvasGlowRadius)
        }
    }

    // MARK: Chrome

    private var chrome: some View {
        VStack(spacing: DS.sm) {
            EditorPaletteLayout(height: DS.capsuleHeight) {
                if configuration.tools.isEmpty { Color.clear.frame(width: 0, height: 0) }
                else { ToolPalette(model: model, configuration: configuration) }
                panelSwitcher
            }
            ToolOptionsBar(model: model)
            HStack(alignment: .top, spacing: 0) {
                if model.showBackdrop {
                    BackdropPanel(model: model).transition(DS.Motion.reveal(from: .leading, reduceMotion: reduceMotion))
                }
                Spacer(minLength: 0)
                if !model.inspector.isEmpty {
                    SidePanel(model: model).transition(DS.Motion.reveal(from: .trailing, reduceMotion: reduceMotion))
                }
            }
            .frame(maxHeight: .infinity)
            ZStack(alignment: .bottom) {
                HStack(alignment: .bottom) { documentBar; Spacer(); exportBar }
                VStack(spacing: DS.sm) {
                    if model.busy || !model.status.isEmpty { toast.transition(DS.Motion.rise(reduceMotion: reduceMotion)) }
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
        .padding(DS.capsulePadding).frame(height: DS.capsuleHeight).modifier(GlassSurface(radius: DS.pill))
    }
    private var zoomBar: some View {
        HStack(spacing: 2) {
            IconButton("minus", label: "Zoom out · ⌘−") { model.zoom(by: 0.8) }
            Menu {
                Button("Fit to window  ⌘0") { model.zoomToFit() }
                Divider()
                ForEach([0.1, 0.25, 0.5, 1, 2, 4, 8, 16, 32], id: \.self) { value in
                    Button("\(Int(value * 100))%") { model.setZoom(value) }
                }
            } label: {
                HStack(spacing: DS.xs) {
                    Text("\(Int(((model.zoom == 0 ? model.displayScale : model.zoom) * 100).rounded()))%").font(DS.mono)
                    Icon("caret-down", size: DS.sm)
                }.frame(width: DS.zoomLabelWidth)
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().help("Zoom")
            IconButton("plus", label: "Zoom in · ⌘+") { model.zoom(by: 1.25) }
        }
        .padding(DS.capsulePadding).frame(height: DS.capsuleHeight).modifier(GlassSurface(radius: DS.pill))
    }

    private var exportBar: some View {
        HStack(spacing: DS.xs) {
            HStack(spacing: DS.xs) {
                Icon("dots-six-vertical", weight: .bold, size: DS.iconSize)
                Text("Drag").font(DS.caption)
            }
            .foregroundStyle(.primary).padding(.horizontal, DS.xs).frame(height: DS.toolButtonSize)
            .contentShape(Capsule())
            .onDrag { dragProvider() }
            .help("Drag the finished image into another app").accessibilityLabel("Drag image")
            IconButton("pin", label: "Pin to screen") { model.export(pin: true) }.disabled(model.pinAction == nil || model.busy)
            ShareButton(model: model).frame(width: DS.toolButtonSize, height: DS.toolButtonSize)
            IconButton("square.and.arrow.down.on.square", label: "Save editable project · ⇧⌘S") { model.saveProject() }
            divider
            Button { model.export(copy: true) } label: { ExportLabel(copy: true, feedback: model.exportFeedback) }
                .buttonStyle(QuietButtonStyle()).disabled(model.busy).help("Copy image · ⌘C")
            HStack(spacing: 0) {
                Button { model.export() } label: { ExportLabel(copy: false, feedback: model.exportFeedback).font(DS.emphasis).padding(.leading, DS.md).padding(.trailing, DS.sm).frame(height: DS.toolButtonSize) }
                    .buttonStyle(.plain).help("Save image · ⌘S")
                Rectangle().fill(DS.onAccent.opacity(0.4)).frame(width: DS.stroke, height: DS.lg)
                Button { choosingFormat.toggle() } label: {
                    HStack(spacing: 3) {
                        Text(ImageExport.formats.first { $0.id == model.format }?.name ?? "PNG").font(DS.mono)
                        Icon("chevron.down", weight: .bold, size: 10)
                    }.foregroundStyle(DS.onAccent).padding(.leading, DS.sm).padding(.trailing, DS.md).frame(height: DS.toolButtonSize).contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle()).help("Format and resolution").accessibilityLabel("Format and resolution")
                .popover(isPresented: $choosingFormat, arrowEdge: .top) {
                    ExportOptions(model: model, dismiss: { choosingFormat = false })
                }
            }
            .foregroundStyle(DS.onAccent).background(DS.accent, in: Capsule())
            .opacity(model.busy ? 0.5 : 1).disabled(model.busy)
        }
        .padding(DS.capsulePadding).frame(height: DS.capsuleHeight).modifier(GlassSurface(radius: DS.pill))
    }

    private var toast: some View {
        HStack(spacing: DS.sm) {
            if model.busy { ProgressView().controlSize(.small) }
            else if model.exportFeedback?.succeeded == false { Icon("warning").foregroundStyle(.primary) }
            else { Icon("check-circle").foregroundStyle(.primary) }
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

private struct ExportLabel: View {
    let copy: Bool
    let feedback: EditorExportFeedback?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @LocalState private var failures = 0

    var body: some View {
        let result = feedback?.copy == copy ? feedback?.succeeded : nil
        let symbol = result.map { $0 ? "check" : "warning" } ?? (copy ? "copy" : "download-simple")
        HStack(spacing: DS.xs) {
            Icon(symbol, weight: result == nil ? .regular : .bold, size: DS.icon)
                .id(symbol).transition(DS.Motion.pop(reduceMotion: reduceMotion))
            Text(copy ? "Copy" : "Save")
        }
        .accessibilityLabel(result.map { $0 ? (copy ? "Copied image" : "Saved image") : (copy ? "Copy failed" : "Save failed") } ?? (copy ? "Copy" : "Save"))
        .animation(DS.Motion.snappy(reduceMotion), value: result)
        .modifier(WriteFailureShake(progress: CGFloat(failures)))
        .onChange(of: result) { _, new in
            if new == false && !reduceMotion { withAnimation(DS.Motion.snappy(false)) { failures += 1 } }
        }
    }
}

private struct WriteFailureShake: GeometryEffect {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: DS.xs * sin(progress * .pi * 4), y: 0))
    }
}

package struct ExportOptions: View {
    @Bindable private var model: EditorModel
    private let dismiss: () -> Void

    package init(model: EditorModel, dismiss: @escaping () -> Void) {
        self.model = model
        self.dismiss = dismiss
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @LocalState private var shown = false

    package var body: some View {
        ZStack {
            if shown {
                VStack(alignment: .leading, spacing: DS.xs) {
                    SectionLabel("File format")
                    ForEach(ImageExport.formats) { format in
                        option(format.name, selected: model.format == format.id) { model.format = format.id }
                    }
                    Hairline()
                    SectionLabel("Resolution")
                    ForEach([1.0, 2.0, 4.0], id: \.self) { scale in
                        option(scale == 1 ? "Original size" : "\(Int(scale))× resample", selected: model.outputMultiplier == scale) {
                            model.outputMultiplier = scale
                        }
                    }
                }.transition(DS.Motion.pop(reduceMotion: reduceMotion))
            }
        }
        .padding(DS.panelPadding).frame(width: DS.pinPopoverWidth)
        .onAppear { withAnimation(DS.Motion.panel(reduceMotion)) { shown = true } }
    }

    private func option(_ title: String, selected: Bool, apply: @escaping () -> Void) -> some View {
        Button { apply(); dismiss() } label: {
            HStack {
                Text(title).font(DS.body)
                Spacer()
                if selected { Icon("check", weight: .bold, size: DS.icon).foregroundStyle(DS.accent) }
            }.padding(.vertical, DS.xs).contentShape(Rectangle())
        }.buttonStyle(PressableStyle()).accessibilityAddTraits(selected ? .isSelected : [])
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

/// Center the palette when possible. At narrower sizes let it use the space between
/// the window buttons and the inspector switcher before resorting to horizontal scrolling.
private struct EditorPaletteLayout: Layout {
    let height: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? DS.editorSize.width, height: height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let palette = subviews[0], switcher = subviews[1]
        let right = bounds.maxX - switcher.sizeThatFits(.unspecified).width
        switcher.place(at: CGPoint(x: right, y: bounds.midY), anchor: .leading, proposal: .unspecified)
        let left = bounds.minX + DS.windowControlsClearance
        let available = max(0, right - DS.sm - left)
        let width = min(available, palette.sizeThatFits(.unspecified).width)
        let x = max(left, min(bounds.midX - width / 2, right - DS.sm - width))
        palette.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(width: width, height: bounds.height))
    }
}

struct ToolPalette: View {
    @Bindable var model: EditorModel
    @Environment(\.colorScheme) private var scheme

    @Namespace private var toolSelection
    let configuration: EditorChrome

    var body: some View {
        let buttons = HStack(spacing: DS.insetStroke) {
            ForEach(Array(configuration.tools.enumerated()), id: \.element) { index, id in
                if configuration.beginsGroup(at: index) { separator }
                if id == "image" {
                    IconButton("image-square", label: "Paste image · ⌘V") { model.pasteImage() }
                } else { toolButton(id) }
            }
        }
        ViewThatFits(in: .horizontal) {
            buttons
            ScrollView(.horizontal) { buttons }.scrollIndicators(.automatic)
        }
        .padding(DS.capsulePadding).frame(height: DS.capsuleHeight).modifier(GlassSurface(radius: DS.pill))
    }
    private var separator: some View {
        Rectangle().fill(DS.hairline(scheme)).frame(width: 1, height: 18).padding(.horizontal, DS.xs)
    }
    private func toolButton(_ id: String) -> some View {
        let info = Self.info(id)
        let key = (model.toolShortcuts[id] ?? info.shortcut).uppercased()
        return IconButton(info.symbol, label: "\(info.title) · \(key)", selected: model.tool == id, selectionSpace: toolSelection) {
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
    public init(document: CaptureDocument, chrome: @escaping @MainActor () -> EditorChrome = { EditorChrome() }) {
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
        let host = NSHostingView(rootView: EditorWindowContent(model: model, chrome: chrome))
        host.sizingOptions = []
        window.contentView = host
        window.setContentSize(size)
        window.center()
        super.init(window: window)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    public func present() { NSApp.activate(ignoringOtherApps: true); showWindow(nil); window?.makeKeyAndOrderFront(nil) }
}

/// Reading the app's observed preferences here also updates editors already on screen.
private struct EditorWindowContent: View {
    let model: EditorModel
    let chrome: @MainActor () -> EditorChrome
    var body: some View { EditorView(model: model, chrome: chrome()) }
}

extension RGBA {
    init(hex: UInt32) {
        let c = DS.components(hex)
        self.init(red: c.red, green: c.green, blue: c.blue)
    }
}
