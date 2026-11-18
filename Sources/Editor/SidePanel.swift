import SwiftUI
import AppKit
import Document
import Render
import DesignSystem
import Recognition
import AI

/// Right-hand panel: text and codes, smart tools, layers, or image details.
struct SidePanel: View {
    @Bindable var model: EditorModel
    @Environment(\.colorScheme) private var scheme

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            if model.inspector == "ask", let ask = model.ask {
                AskView(model: ask, editor: model, close: { model.inspector = "" })
                    .frame(width: DS.Ask.editorWidth)
            } else { inspectorContent }
        }
        .id(model.inspector)
        .transition(DS.Motion.reveal(from: .trailing, reduceMotion: reduceMotion))
        .animation(DS.Motion.panel(reduceMotion), value: model.inspector)
    }

    private var inspectorContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(DS.title)
                Spacer()
                IconButton("xmark", label: "Close panel", size: 24) { model.inspector = "" }
            }
            .padding(.horizontal, DS.lg).padding(.top, DS.lg).padding(.bottom, DS.md)
            ScrollView {
                VStack(alignment: .leading, spacing: DS.lg) {
                    switch model.inspector {
                    case "layers": layers
                    case "info": details
                    case "intelligence": smartTools
                    default: recognition
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.lg).padding(.bottom, DS.lg)
            }
            .scrollIndicators(.hidden)
        }
        .frame(width: DS.sidePanelWidth)
        .modifier(GlassSurface())
    }

    private var title: String {
        switch model.inspector {
        case "layers": "Layers"
        case "info": "Details"
        case "intelligence": "Smart tools"
        default: "Text and codes"
        }
    }

    // MARK: Layers

    private var layers: some View {
        VStack(alignment: .leading, spacing: DS.sm) {
            if model.document.layers.isEmpty {
                emptyState("square.3.layers.3d", "No annotations yet", "Pick a tool and draw on the image. Each mark becomes a layer you can restyle or remove.")
            }
            ForEach(model.document.layers.reversed()) { layer in
                let selected = model.selected.contains(layer.id)
                HStack(spacing: DS.sm) {
                    Icon(ToolRegistry.tool(layer.kind.rawValue)?.symbol ?? "photo")
                        .font(.system(size: 12, weight: .medium)).frame(width: 26, height: 26)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .background(selected ? DS.accent : DS.hover(scheme), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    Text(layer.text.isEmpty ? (ToolRegistry.tool(layer.kind.rawValue)?.title ?? layer.kind.rawValue.capitalized) : layer.text)
                        .font(DS.body).lineLimit(1)
                    Spacer()
                    if layer.kind != .image && ![.blur, .pixelate, .spotlight].contains(layer.kind) {
                        Circle().fill(Color(layer.color.nsColor)).frame(width: 10, height: 10).overlay(Circle().strokeBorder(DS.hairline(scheme)))
                    }
                    Button { model.selected = [layer.id]; model.deleteSelection() } label: {
                        Icon("trash", size: 13).foregroundStyle(.secondary).frame(width: 22, height: 22)
                    }.buttonStyle(.plain).help("Delete layer")
                }
                .padding(6)
                .background(selected ? DS.hover(scheme) : .clear, in: RoundedRectangle(cornerRadius: DS.smallRadius, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture { model.selected = [layer.id]; model.tool = "select" }
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            HStack(spacing: DS.sm) {
                Icon("lock.fill", size: 13).frame(width: 26, height: 26).foregroundStyle(.secondary)
                    .background(DS.card(scheme), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Original image").font(DS.body)
                    Text("Never modified").font(DS.caption).foregroundStyle(.tertiary)
                }
            }.padding(6)
        }
    }

    // MARK: Details

    private var details: some View {
        let doc = model.document, size = DocumentRenderer.layout(model.current).size
        return VStack(alignment: .leading, spacing: DS.md) {
            Card {
                row("Export size", "\(Int(size.width)) × \(Int(size.height)) px")
                Hairline().padding(.vertical, DS.sm)
                row("Original", "\(doc.width) × \(doc.height) px")
                Hairline().padding(.vertical, DS.sm)
                row("Points", "\(Int(Double(doc.width) / doc.scale)) × \(Int(Double(doc.height) / doc.scale)) pt")
                Hairline().padding(.vertical, DS.sm)
                row("Scale", String(format: "%.0f×", doc.scale))
            }
            Card {
                row("File size", ByteCountFormatter.string(fromByteCount: Int64(doc.original.count), countStyle: .file))
                Hairline().padding(.vertical, DS.sm)
                row("Color", doc.preserveColorProfile == true ? "Display profile" : "sRGB")
                Hairline().padding(.vertical, DS.sm)
                row("Layers", "\(doc.layers.count)")
            }
            Card {
                row("Source", doc.source)
                Hairline().padding(.vertical, DS.sm)
                row("Captured", doc.date.formatted(date: .abbreviated, time: .shortened))
            }
            if doc.crop != nil {
                Button("Restore full image") { model.commit { $0.crop = nil } }.buttonStyle(QuietButtonStyle())
            }
        }
    }
    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(DS.body).foregroundStyle(.secondary)
            Spacer(minLength: DS.md)
            Text(value).font(DS.mono).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
    }

    // MARK: Smart tools

    private var smartTools: some View {
        VStack(alignment: .leading, spacing: DS.md) {
            HStack(spacing: 6) {
                Icon("lock.shield", weight: .bold, size: 13)
                Text("Runs on this Mac. Nothing is uploaded.").font(DS.caption)
            }.foregroundStyle(.secondary)
            SectionLabel("Clean up")
            Card(padding: DS.xs) {
                action("eye.slash", "Smart redact", "Hide emails, keys, and faces", .redact)
                action("person.crop.rectangle", "Lift subject", "Remove the background", .removeBackground)
                actionRow("eraser", "Patch erase", "Fill a selected area") {
                    guard let region = model.document.layers.first(where: { model.selected.contains($0.id) })?.rect else {
                        model.message = AIError.invalidSelection.localizedDescription; return
                    }
                    model.performAI(.erase(region))
                }
            }
            SectionLabel("Extract")
            Card(padding: DS.xs) {
                action("text.alignleft", "Copy as Markdown", "Keep headings and lists", .markdown)
                action("tablecells", "Table to CSV", "Rows and columns as text", .csv)
                action("chevron.left.forwardslash.chevron.right", "Extract code", "Code blocks only", .code)
                action("text.bubble", "Describe", "Alt text for this image", .describe)
                action("character.cursor.ibeam", "Suggest a name", "A file name from the content", .filename)
            }
            SectionLabel("Point at something")
            HStack(spacing: DS.sm) {
                field("A word, e.g. Save", text: $model.aiPrompt) { model.performAI(.annotate(model.aiPrompt)) }
                Button("Add arrow") { model.performAI(.annotate(model.aiPrompt)) }
                    .buttonStyle(QuietButtonStyle()).disabled(model.busy || model.aiPrompt.isEmpty)
            }
            SectionLabel("Translate in place")
            HStack(spacing: DS.sm) {
                Picker("Target language", selection: $model.translationLanguage) {
                    Text("English").tag("en"); Text("Spanish").tag("es"); Text("French").tag("fr")
                    Text("German").tag("de"); Text("Japanese").tag("ja"); Text("Chinese").tag("zh-Hans")
                }.labelsHidden()
                Button("Translate") { model.performAI(.translate(model.translationLanguage)) }
                    .buttonStyle(QuietButtonStyle()).disabled(model.busy)
            }
            Text("Translation uses language packs already installed on this Mac.")
                .font(DS.caption).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func action(_ symbol: String, _ title: String, _ subtitle: String, _ request: AIRequest) -> some View {
        actionRow(symbol, title, subtitle) { model.performAI(request) }
    }
    private func actionRow(_ symbol: String, _ title: String, _ subtitle: String, perform: @escaping () -> Void) -> some View {
        ActionRow(symbol: symbol, title: title, subtitle: subtitle, action: perform).disabled(model.busy)
    }

    // MARK: Text and codes

    private var recognition: some View {
        VStack(alignment: .leading, spacing: DS.md) {
            if model.busy && model.recognition == nil {
                HStack(spacing: DS.sm) { ProgressView().controlSize(.small); Text("Reading the image…").font(DS.body).foregroundStyle(.secondary) }
            }
            if !model.redactions.isEmpty { redactionReview }
            if !model.generatedText.isEmpty {
                SectionLabel("Result")
                Card {
                    Text(model.generatedText).font(DS.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                Button { model.copyText(model.generatedText) } label: { Label { Text("Copy result") } icon: { Icon("doc.on.doc", size: 16) } }.buttonStyle(QuietButtonStyle())
            }
            if let result = model.recognition {
                ForEach(result.codes) { code in codeCard(code) }
                if result.text.isEmpty && result.codes.isEmpty {
                    emptyState("text.viewfinder", "Nothing to read", "No text or codes were found in this image.")
                } else if !result.text.isEmpty {
                    HStack {
                        SectionLabel("\(result.text.count) lines of text")
                        Spacer()
                        Button("Copy all") { model.copyText(result.transcript) }.buttonStyle(.plain).font(DS.caption).foregroundStyle(DS.actionInk(scheme))
                    }
                    Button { model.tool = "liveText" } label: { Label { Text("Select text on the image") } icon: { Icon("cursorarrow.rays", size: 16) } }
                        .buttonStyle(QuietButtonStyle())
                    Card(padding: DS.xs) {
                        ForEach(result.text) { region in
                            Button { model.copyText(region.text) } label: {
                                Text(region.text).font(DS.body).lineLimit(2).multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, DS.sm).padding(.vertical, 6).contentShape(Rectangle())
                            }.buttonStyle(.plain).help("Click to copy")
                        }
                    }
                }
            } else if !model.busy && model.redactions.isEmpty && model.generatedText.isEmpty {
                emptyState("text.viewfinder", "Read this image", "Find text, links, and QR codes. Everything stays on your Mac.")
                Button { model.recognize() } label: { Label { Text("Recognize text") } icon: { Icon("text.viewfinder", size: 16) } }.buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    private func codeCard(_ code: CodeRegion) -> some View {
        Card {
            HStack(spacing: DS.sm) {
                Icon("qrcode", size: 17)
                Text("Code found").font(DS.emphasis)
            }
            Text(code.payload).font(DS.mono).textSelection(.enabled).lineLimit(4).padding(.vertical, DS.sm)
            HStack(spacing: DS.sm) {
                Button("Copy") { model.copyText(code.payload) }.buttonStyle(QuietButtonStyle())
                if let url = URL(string: code.payload), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                    Button("Open link") { NSWorkspace.shared.open(url) }.buttonStyle(PrimaryButtonStyle())
                }
            }
        }
    }

    private var redactionReview: some View {
        VStack(alignment: .leading, spacing: DS.md) {
            SectionLabel("Review redactions")
            Card(padding: DS.sm) {
                ForEach(model.redactions) { candidate in
                    Toggle(isOn: Binding(get: { model.acceptedRedactions.contains(candidate.id) }, set: { enabled in
                        if enabled { model.acceptedRedactions.insert(candidate.id) } else { model.acceptedRedactions.remove(candidate.id) }
                    })) { Text(candidate.label).font(DS.body).lineLimit(1) }
                        .toggleStyle(.checkbox).padding(.vertical, 3)
                }
            }
            Button("Cover \(model.acceptedRedactions.count) selected") { model.applyRedactions() }
                .buttonStyle(PrimaryButtonStyle()).disabled(model.acceptedRedactions.isEmpty)
            Text("Covers stay editable in the project. Share an exported image, not the project, when hiding sensitive content.")
                .font(DS.caption).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Pieces

    private func emptyState(_ symbol: String, _ title: String, _ message: String) -> some View {
        VStack(spacing: DS.sm) {
            Icon(symbol, size: 29).foregroundStyle(.tertiary)
            Text(title).font(DS.emphasis)
            Text(message).font(DS.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity).padding(.vertical, DS.xl)
    }
    private func field(_ prompt: String, text: Binding<String>, submit: @escaping () -> Void) -> some View {
        TextField(prompt, text: text).textFieldStyle(.plain).font(DS.body).onSubmit(submit)
            .padding(.horizontal, DS.sm).frame(height: DS.toolButton)
            .background(DS.card(scheme), in: RoundedRectangle(cornerRadius: DS.controlRadius, style: .continuous))
    }
}

/// A tappable row with an icon tile, a title, and a one-line explanation.
struct ActionRow: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    @LocalState private var hovering = false
    let symbol: String
    let title: String
    let subtitle: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.md) {
                Icon(symbol, size: 16).frame(width: 28, height: 28)
                    .foregroundStyle(DS.actionInk(scheme))
                    .background(DS.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(DS.body.weight(.medium))
                    Text(subtitle).font(DS.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(DS.sm)
            .background(hovering && enabled ? DS.hover(scheme) : .clear, in: RoundedRectangle(cornerRadius: DS.controlRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).opacity(enabled ? 1 : 0.5)
        .onHover { hovering = $0 }
    }
}

struct EditorPanelSwitcher: View {
    let model: EditorModel
    @Namespace private var tile
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @LocalState private var hovered: String?

    var body: some View {
        HStack(spacing: DS.xs / 2) {
            tab("scan", "Text and codes", "recognition")
            tab("magic-wand", "Smart tools", "intelligence")
            if model.askOptions != nil { tab("chat-circle-dots", "Ask", "ask") }
            tab("stack", "Layers", "layers")
            tab("info", "Details", "info")
        }
        .padding(DS.md / 2).frame(height: DS.barHeight).modifier(GlassSurface(radius: DS.pill))
    }

    private func tab(_ symbol: String, _ label: String, _ id: String) -> some View {
        let selected = model.inspector == id
        return Button {
            withAnimation(DS.Motion.panel(reduceMotion)) {
                if selected { model.inspector = "" }
                else if id == "ask" { model.openAsk() }
                else {
                    model.inspector = id
                    if id == "recognition", model.recognition == nil { model.recognize() }
                }
            }
        } label: {
            Icon(symbol, weight: selected ? .fill : .regular, size: DS.iconSize)
                .foregroundStyle(selected ? DS.onAccent : Color.primary)
                .frame(minWidth: DS.xl, idealWidth: DS.toolButton, maxWidth: DS.toolButton, minHeight: DS.toolButton, maxHeight: DS.toolButton)
                .background {
                    if selected {
                        if reduceMotion { RoundedRectangle(cornerRadius: DS.controlRadius).fill(DS.accent) }
                        else { RoundedRectangle(cornerRadius: DS.controlRadius).fill(DS.accent).matchedGeometryEffect(id: "active", in: tile) }
                    } else if hovered == id { RoundedRectangle(cornerRadius: DS.controlRadius).fill(DS.hover(scheme)) }
                }.contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle()).accessibilityLabel(label).help(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .onHover { over in withAnimation(DS.Motion.hover(reduceMotion)) { hovered = over ? id : nil } }
        .animation(DS.Motion.snappy(reduceMotion), value: model.inspector)
    }
}
