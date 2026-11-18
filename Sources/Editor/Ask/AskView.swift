import SwiftUI
import AI
import DesignSystem
import Render

public struct AskView: View {
    @Bindable var model: AskModel
    let editor: EditorModel
    let close: () -> Void
    let openEditor: (() -> EditorModel)?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @FocusState private var focused: Bool
    @LocalState private var followsStream = true

    public init(model: AskModel, editor: EditorModel, close: @escaping () -> Void, openEditor: (() -> EditorModel)? = nil) {
        self.model = model; self.editor = editor; self.close = close; self.openEditor = openEditor
    }

    private var provider: AssistantProvider { model.options.provider }
    private var reveal: AnyTransition { DS.Motion.reveal(from: .bottom, reduceMotion: reduced) }

    public var body: some View {
        VStack(spacing: 0) {
            header
            if model.usage?.limitReached == true {
                state("clock", "Usage limit reached", limitDetail) {
                    Capsule().fill(DS.slate.opacity(DS.mutedOpacity)).frame(width: DS.Ask.editorWidth / 2, height: DS.xs)
                    alternateProvider
                }.transition(reveal)
                Text("Switching providers keeps this conversation").font(DS.caption).foregroundStyle(.secondary).padding(DS.md)
            } else if let availability = model.availability, !availability.isReady {
                accountState(availability).transition(reveal)
                if let error = model.error { errorNotice(error) }
            } else {
                transcript
                if model.awaitingConsent { consent.transition(reveal) }
                else if let error = model.error { errorNotice(error).transition(reveal) }
                else if !model.options.suggestions.isEmpty && !model.isStreaming { suggestions }
                composer
                footer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(GlassSurface())
        .animation(DS.Motion.panel(reduced), value: model.awaitingConsent)
        .animation(DS.Motion.panel(reduced), value: model.error)
        .animation(DS.Motion.panel(reduced), value: model.usage?.limitReached)
        .task { if model.availability == nil { await model.refreshAvailability() } }
        .onExitCommand { escape() }
    }

    private var header: some View {
        HStack(spacing: DS.sm) {
            Text("Ask").font(DS.title)
            Menu {
                Button("ChatGPT") { model.switchProvider(.chatgpt) }.disabled(provider == .chatgpt)
                Button("Claude") { model.switchProvider(.claude) }.disabled(provider == .claude)
            } label: {
                HStack(spacing: DS.xs) {
                    Icon(provider == .chatgpt ? "aperture" : "sparkle", size: DS.md)
                    Text(provider.title)
                    Icon("caret-down", weight: .bold, size: DS.sm + DS.xs / 2)
                }.font(DS.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, DS.sm).padding(.vertical, DS.xs).background(DS.card(scheme), in: Capsule())
                    .contentShape(Capsule())
            }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("Provider: \(provider.title)").help("Switch provider")
            Spacer()
            Menu {
                if let openEditor { Button("Open in editor") { _ = openEditor() }; Divider() }
                Button("New conversation") { editor.pickingAskRegion = false; model.newConversation() }
                Button("Use ChatGPT") { model.switchProvider(.chatgpt) }.disabled(provider == .chatgpt)
                Button("Use Claude") { model.switchProvider(.claude) }.disabled(provider == .claude)
                Divider()
                Button("Copy conversation") { editor.copyText(model.transcript) }.disabled(model.transcript.isEmpty)
            } label: { Icon("dots-three", weight: .bold, size: DS.iconSize).frame(width: DS.xl, height: DS.xl) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Conversation options").help("Conversation options")
            IconButton("x", label: "Close Ask", size: DS.xl, action: close)
        }.padding(.horizontal, DS.lg).padding(.top, DS.md).padding(.bottom, DS.md)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.lg) {
                    contextCard
                    if model.messages.isEmpty { intro.transition(DS.Motion.rise(reduceMotion: reduced)) }
                    ForEach(model.messages) { message in
                        messageView(message).transition(DS.Motion.rise(reduceMotion: reduced))
                    }
                    Color.clear.frame(height: DS.stroke).id("bottom")
                }
                .padding(.horizontal, DS.lg).padding(.bottom, DS.sm)
                .animation(DS.Motion.arrive(reduced), value: model.messages.count)
                .animation(DS.Motion.gentle(reduced), value: model.messages.isEmpty)
            }
            .onScrollPhaseChange { _, phase, context in
                if phase == .idle {
                    followsStream = context.geometry.visibleRect.maxY + DS.xxl >= context.geometry.contentSize.height
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height } action: { before, after in
                if after > before, model.isStreaming, followsStream {
                    withAnimation(reduced ? nil : DS.Motion.gentle(false)) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: model.messages.count) { withAnimation(DS.Motion.gentle(reduced)) { proxy.scrollTo("bottom", anchor: .bottom) } }
        }
    }

    private var contextCard: some View {
        let document = model.captureDocument ?? editor.current
        let size = DocumentRenderer.layout(document).size
        let age = Date.now.timeIntervalSince(document.date) < 60 ? "captured just now" : document.date.formatted(.relative(presentation: .named))
        return HStack(spacing: DS.md) {
            if let image = model.captureImage ?? editor.image {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
                    .frame(width: DS.Ask.thumbnail.width, height: DS.Ask.thumbnail.height)
                    .clipShape(RoundedRectangle(cornerRadius: DS.xs))
            }
            VStack(alignment: .leading, spacing: DS.xs / 2) {
                Text(document.source.replacingOccurrences(of: " — ", with: " · ")).font(DS.body.weight(.medium)).lineLimit(1)
                HStack(spacing: DS.xs) {
                    Text(verbatim: "\(Int(size.width)) × \(Int(size.height))").font(DS.mono)
                    Text("·").accessibilityHidden(true)
                    Text(age).lineLimit(1)
                }.font(DS.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.padding(DS.sm).background(DS.card(scheme), in: RoundedRectangle(cornerRadius: DS.groupRadius))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func messageView(_ message: AskMessage) -> some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: DS.xxl)
                VStack(alignment: .leading, spacing: DS.xs) {
                    ForEach(Array(message.attachments.enumerated()), id: \.offset) { _, label in regionChip(label) }
                    if let action = message.action {
                        Label { Text(action.title).font(DS.emphasis) } icon: { Icon(action.icon, weight: .fill, size: DS.icon) }
                            .foregroundStyle(DS.actionInk(scheme))
                        if !message.typed.isEmpty { Text(message.typed).font(DS.body).textSelection(.enabled) }
                    } else {
                        Text(message.text).font(DS.body).textSelection(.enabled)
                    }
                }.padding(.horizontal, DS.md).padding(.vertical, DS.sm)
                    .background(DS.hover(scheme), in: UnevenRoundedRectangle(topLeadingRadius: DS.Ask.bubble, bottomLeadingRadius: DS.Ask.bubble,
                                                                            bottomTrailingRadius: DS.xs, topTrailingRadius: DS.Ask.bubble))
            }
        } else if message.status == .streaming && message.text.isEmpty {
            AskThinking(provider: provider.title).transition(DS.Motion.pop(reduceMotion: reduced))
        } else if !message.text.isEmpty || message.status == .streaming {
            VStack(alignment: .leading, spacing: DS.sm) {
                AskReply(text: message.text, streaming: message.status == .streaming, copy: editor.copyText)
                if message.status == .done && !message.text.isEmpty {
                    HStack(spacing: DS.sm) {
                        replyButton("copy", "Copy") { editor.copyText(message.text) }
                        replyButton("text-t", "Add as text") { (openEditor?() ?? editor).addReply(message.text) }
                        if let rect = model.matchingRegion(in: message.text, document: editor.document, editorText: editor.recognition?.text ?? []) {
                            replyButton("crosshair-simple", "Show on image") { (openEditor?() ?? editor).flashAskRegion(rect) }
                        }
                    }
                }
            }
        }
    }

    private func replyButton(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.xs) { Icon(icon, size: DS.md); Text(title).font(DS.caption) }.padding(.vertical, DS.xs)
        }.buttonStyle(PressableStyle()).foregroundStyle(.secondary).help(title)
    }

    private func regionChip(_ label: String) -> some View {
        HStack(spacing: DS.xs) { Icon("selection-plus", size: DS.md); Text(label).font(DS.mono) }
            .padding(.horizontal, DS.sm).padding(.vertical, DS.xs)
            .foregroundStyle(DS.actionInk(scheme)).background(DS.accent.opacity(DS.subtleOpacity), in: RoundedRectangle(cornerRadius: DS.controlRadius))
    }

    private var actions: [AskQuickAction] { model.options.suggestions.map(AskQuickAction.named) }

    private var intro: some View {
        VStack(alignment: .leading, spacing: DS.xs) {
            Text("What would you like to know?").font(DS.emphasis)
            Text("Pick an action below, or type a question. Ask sees this capture\(model.options.includeRecognizedText ? " and its text" : "").")
                .font(DS.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(.top, DS.xs).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var suggestions: some View {
        Group {
            if actions.count <= 4 {
                HStack(spacing: DS.xs) {
                    ForEach(Array(actions.enumerated()), id: \.element.id) { i, action in actionButton(action, index: i, fill: true) }
                }
            } else {
                AskChipLayout {
                    ForEach(Array(actions.enumerated()), id: \.element.id) { i, action in actionButton(action, index: i, fill: false) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, DS.md).padding(.bottom, DS.sm)
    }

    private func actionButton(_ action: AskQuickAction, index: Int, fill: Bool) -> some View {
        AskActionButton(action: action, fill: fill) { model.ask(action, document: editor.current) }
            .staggeredAppear(index)
            .help(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? action.prompt : "\(action.title) with your note")
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: DS.xs) {
            if !model.regions.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: DS.xs) {
                        ForEach(model.regions) { region in
                            Button { model.removeRegion(region.id) } label: { regionChip(region.label) }
                                .buttonStyle(PressableStyle()).accessibilityLabel("Remove \(region.label)").help("Remove region")
                        }
                    }
                }.scrollIndicators(.hidden)
            }
            TextField(model.messages.isEmpty ? "Ask anything about this capture…" : "Ask a follow-up…", text: $model.draft, axis: .vertical)
                .lineLimit(1...5).textFieldStyle(.plain).font(DS.body).focused($focused)
                .accessibilityLabel("Question about this capture").disabled(model.awaitingConsent)
            HStack {
                IconButton("selection-plus", label: "Attach a region", selected: editor.pickingAskRegion, size: DS.Ask.send) {
                    let target = openEditor?() ?? editor; focused = false; target.pickingAskRegion.toggle()
                }.disabled(model.awaitingConsent || model.isStreaming)
                if editor.pickingAskRegion { Text("Drag on the image").font(DS.caption).foregroundStyle(.secondary) }
                Spacer()
                Button { model.isStreaming ? model.stop() : model.send(document: editor.current) } label: {
                    HStack(spacing: DS.xs) {
                        Icon(model.isStreaming ? "stop" : "arrow-up", weight: .bold, size: DS.icon)
                            .id(model.isStreaming).transition(.opacity)
                        if model.isStreaming { Text("Stop").font(DS.caption).transition(.opacity) }
                    }
                    .padding(.horizontal, DS.sm).frame(minWidth: DS.Ask.send, minHeight: DS.Ask.send)
                    .foregroundStyle(model.canSend ? DS.onAccent : Color.secondary)
                    .background(model.canSend ? DS.accent : DS.hover(scheme), in: Capsule())
                }
                .buttonStyle(PressableStyle()).keyboardShortcut(.return, modifiers: .command)
                .accessibilityLabel(model.isStreaming ? "Stop reply" : "Send question")
                .help(model.isStreaming ? "Stop reply" : "Send · ⌘↩")
                .disabled(!model.canSend && !model.isStreaming).animation(DS.Motion.snappy(reduced), value: model.isStreaming)
            }
        }.padding(DS.md)
        .background(DS.card(scheme), in: RoundedRectangle(cornerRadius: DS.Ask.bubble))
        .overlay(RoundedRectangle(cornerRadius: DS.Ask.bubble).strokeBorder(focused ? DS.accent : DS.hairline(scheme)))
        .padding(.horizontal, DS.md).padding(.bottom, DS.sm)
    }

    private var footer: some View {
        HStack {
            Text("\(provider.title) via \(provider.toolName)")
            Spacer()
            if let fraction = model.usage?.usedFraction, fraction.isFinite {
                Text("\(min(1, max(0, fraction)), format: .percent.precision(.fractionLength(0))) of limit").font(DS.mono)
            } else { Text("⌘↩ send").font(DS.mono) }
        }.font(DS.caption).foregroundStyle(.secondary).padding(.horizontal, DS.lg).padding(.bottom, DS.md)
    }

    private var consent: some View {
        VStack(alignment: .leading, spacing: DS.sm) {
            Label { Text("Send this capture to \(provider.vendor)?").font(DS.emphasis) } icon: { Icon("export", size: DS.icon) }
            Text(consentDetail)
                .font(DS.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Cancel") { model.cancelConsent() }.buttonStyle(.plain).font(DS.caption)
                Spacer()
                Button("Hide it, then send") { model.confirm(redact: true) }.buttonStyle(QuietButtonStyle())
                Button("Send") { model.confirm(redact: false) }.buttonStyle(PrimaryButtonStyle())
            }
        }.padding(DS.md).background(DS.card(scheme), in: RoundedRectangle(cornerRadius: DS.Ask.bubble))
            .padding(.horizontal, DS.md).padding(.bottom, DS.sm)
    }

    private var consentDetail: String {
        var parts = ["the image"]
        if model.options.includeRecognizedText { parts.append("its recognized text") }
        if model.includesEarlierMessages { parts.append("excerpts from this conversation") }
        let contents = ListFormatter.localizedString(byJoining: parts)
        let privacy: String
        if let count = model.sensitiveCount, count > 0 {
            privacy = "Smart redact found \(count) sensitive \(count == 1 ? "detail" : "details")."
        } else { privacy = "Smart redact can cover sensitive details first." }
        return "\(provider.title) will receive \(contents) through \(provider.toolName). \(privacy)"
    }

    private var limitDetail: String {
        let reset = model.usage?.resetsAt.map { "Your \(provider.title) plan resets \($0.formatted(date: .abbreviated, time: .shortened))." }
        return (reset ?? "Your \(provider.title) plan has reached its usage limit.") + " Recognized text, copying, and smart tools still work on this Mac."
    }
    private var alternateProvider: some View {
        Button("Ask \(model.otherProvider.title) instead") { model.switchProvider(model.otherProvider) }.buttonStyle(QuietButtonStyle())
    }

    @ViewBuilder private func accountState(_ availability: AssistantAvailability) -> some View {
        switch availability {
        case .signedOut:
            state("sign-in", model.waitingForBrowser ? "Waiting for your browser…" : "Sign in with \(provider.title)",
                  "Ask questions about your captures using your \(provider.title) plan. Sign-in opens in your \(provider == .chatgpt ? "browser" : "terminal").") {
                Button("Sign in with \(provider.title)") { model.signIn() }.buttonStyle(PrimaryButtonStyle()).disabled(model.waitingForBrowser)
                Button("Use \(model.otherProvider.title) instead") { model.switchProvider(model.otherProvider) }
                    .buttonStyle(.plain).font(DS.body).foregroundStyle(.secondary)
            }
        case .notInstalled:
            state("terminal-window", "Install \(provider.toolName)", "How to install") {
                if provider == .chatgpt { Text("npm i -g @openai/codex").font(DS.mono).textSelection(.enabled) }
                else { Link("Claude Code installation guide", destination: URL(string: "https://code.claude.com/docs/en/setup")!) }
                Button("Check again") { Task { await model.refreshAvailability() } }.buttonStyle(QuietButtonStyle())
                alternateProvider
            }
        case .unsupportedVersion(let found, let minimum):
            state("terminal-window", "Update \(provider.toolName)", "Version \(found) is installed. Ask needs version \(minimum) or later.") {
                Button("Check again") { Task { await model.refreshAvailability() } }.buttonStyle(QuietButtonStyle())
            }
        case .ready: EmptyView()
        }
    }

    private func state<Actions: View>(_ icon: String, _ title: String, _ detail: String, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(spacing: DS.md) {
            Icon(icon, size: DS.xl).frame(width: DS.Ask.cell, height: DS.Ask.cell)
                .background(DS.card(scheme), in: RoundedRectangle(cornerRadius: DS.groupRadius))
            Text(title).font(DS.title)
            Text(detail).font(DS.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            actions()
        }.multilineTextAlignment(.center).padding(DS.xl).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func errorNotice(_ text: String) -> some View {
        HStack {
            Icon("warning-circle")
            Text(text).font(DS.body).textSelection(.enabled)
            Spacer()
            Button("Retry") { if case .signedOut = model.availability { model.signIn() } else { model.retry() } }.buttonStyle(QuietButtonStyle())
        }.padding(DS.md).background(DS.card(scheme), in: RoundedRectangle(cornerRadius: DS.groupRadius)).padding(DS.md)
    }

    private func escape() {
        if editor.pickingAskRegion { editor.pickingAskRegion = false }
        else if model.isStreaming { model.stop() }
        else if model.awaitingConsent { model.cancelConsent() }
        else if !model.draft.isEmpty { model.draft = "" }
        else { close() }
    }
}

/// A quick action: icon over title in a soft tile, lifting on hover.
private struct AskActionButton: View {
    let action: AskQuickAction
    let fill: Bool
    let perform: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.isEnabled) private var enabled
    @LocalState private var hovering = false
    var body: some View {
        Button(action: perform) {
            HStack(spacing: DS.xs) {
                Icon(action.icon, weight: hovering ? .fill : .regular, size: DS.icon)
                    .foregroundStyle(hovering && enabled ? DS.actionInk(scheme) : Color.secondary)
                Text(action.title).font(DS.caption.weight(.semibold)).lineLimit(1)
            }
            .padding(.horizontal, DS.sm).frame(maxWidth: fill ? .infinity : nil).frame(height: DS.Ask.send)
            .background(hovering && enabled ? DS.hover(scheme) : DS.card(scheme), in: RoundedRectangle(cornerRadius: DS.controlRadius + DS.xs / 2, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.controlRadius + DS.xs / 2, style: .continuous)
                .strokeBorder(hovering && enabled ? DS.accent.opacity(DS.outlineOpacity * 2) : DS.hairline(scheme)))
            .contentShape(RoundedRectangle(cornerRadius: DS.controlRadius + DS.xs / 2))
            .opacity(enabled ? 1 : DS.mutedOpacity)
        }
        .buttonStyle(PressableStyle())
        .onHover { over in withAnimation(DS.Motion.hover(reduced)) { hovering = over } }
        .accessibilityLabel(action.title)
    }
}

/// Shown while a reply has started but no words have arrived yet.
private struct AskThinking: View {
    let provider: String
    @Environment(\.accessibilityReduceMotion) private var reduced
    @LocalState private var phase = false
    var body: some View {
        HStack(spacing: DS.sm) {
            HStack(spacing: DS.xs) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(Color.secondary).frame(width: DS.xs + DS.xs / 2, height: DS.xs + DS.xs / 2)
                        .opacity(phase ? 1 : 0.3).scaleEffect(phase && !reduced ? 1 : 0.7)
                        .animation(reduced || DS.rendersOffscreen ? nil : DS.Motion.gentle(false).repeatForever(autoreverses: true)
                            .delay(Double(i) * DS.Motion.stagger(4, reduceMotion: false)), value: phase)
                }
            }
            Text("\(provider) is looking at your capture…").font(DS.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, DS.xs)
        .onAppear { phase = true }
        .accessibilityElement(children: .ignore).accessibilityLabel("\(provider) is thinking")
    }
}

/// Wraps editable suggestion titles at their intrinsic widths.
private struct AskChipLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        positions(width: proposal.width ?? DS.Ask.editorWidth, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = positions(width: bounds.width, subviews: subviews)
        for (view, point) in zip(subviews, layout.points) {
            view.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: ProposedViewSize(width: bounds.width < view.sizeThatFits(.unspecified).width ? bounds.width : nil, height: nil))
        }
    }
    private func positions(width: CGFloat, subviews: Subviews) -> (points: [CGPoint], size: CGSize) {
        var points: [CGPoint] = [], x: CGFloat = 0, y: CGFloat = 0, height: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += height + DS.xs; height = 0 }
            points.append(CGPoint(x: x, y: y)); x += size.width + DS.xs; height = max(height, size.height)
        }
        return (points, CGSize(width: width, height: y + height))
    }
}
