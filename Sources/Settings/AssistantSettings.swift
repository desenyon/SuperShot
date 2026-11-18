import AI
import AppKit
import DesignSystem
import SwiftUI

private typealias S = DS.Preferences

struct AssistantSettings: View {
    @Bindable var store: SettingsStore
    let factory: (AssistantProvider) -> any AssistantService
    @LocalState private var availability: [AssistantProvider: AssistantAvailability] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @Environment(\.settingsCompact) private var compact
    private var selected: AssistantProvider? { AssistantProvider(rawValue: store.preferences.assistant.provider) }

    var body: some View {
        VStack(alignment: .leading, spacing: S.sectionGap) {
            SettingsGroup(title: "Provider") {
                ForEach(AssistantProvider.allCases) { provider in
                    providerRow(provider)
                        .task(id: selected) {
                            // The account view refreshes the selected tool, including after login/logout.
                            guard provider != selected else { return }
                            let state = await factory(provider).availability()
                            if !Task.isCancelled { availability[provider] = state }
                        }
                    SettingsDivider()
                }
                providerRow(nil)
            }
            if let selected {
                AssistantAccountSettings(service: factory(selected), availability: Binding(
                    get: { availability[selected] }, set: { availability[selected] = $0 }),
                    model: $store.preferences.assistant.model)
                    .id(selected).transition(DS.Motion.rise(reduceMotion: reduceMotion))
            }
            SettingsGroup(title: "Before sending", index: 2) {
                SettingsRow("Ask before sending a capture", "Confirm the first upload in each conversation.") {
                    SettingsToggle(label: "Ask before sending a capture", isOn: $store.preferences.assistant.confirmBeforeSending)
                }
                SettingsDivider()
                SettingsRow("Include recognized text", "Send text recognized on this Mac alongside the image.") {
                    SettingsToggle(label: "Include recognized text", isOn: $store.preferences.assistant.includeRecognizedText)
                }
                SettingsDivider()
                SettingsRow("Hide sensitive details first", "Apply Smart redact before sharing the image.") {
                    SettingsToggle(label: "Hide sensitive details first", isOn: $store.preferences.assistant.redactBeforeSending)
                }
            }.disabled(selected == nil)
            SettingsGroup(title: "Conversations", index: 3) {
                SettingsRow("Keep conversations with captures", "Save the thread with its capture in History.") {
                    SettingsToggle(label: "Keep conversations with captures", isOn: $store.preferences.assistant.keepConversations)
                }
                SettingsDivider()
                SuggestionSettings(suggestions: $store.preferences.assistant.suggestions)
            }.disabled(selected == nil)
        }
    }

    private func providerRow(_ provider: AssistantProvider?) -> some View {
        let id = provider?.rawValue ?? "off"
        let active = store.preferences.assistant.provider == id
        let state = provider.flatMap { availability[$0] }
        return VStack(alignment: .leading, spacing: DS.xs) {
            Button {
                guard !active else { return }
                withAnimation(DS.Motion.snappy(reduceMotion)) {
                    store.preferences.assistant.model = nil
                    store.preferences.assistant.provider = id
                }
            } label: {
                HStack(spacing: DS.sm) {
                    Circle().strokeBorder(S.accent(scheme), lineWidth: S.focusWidth)
                        .overlay {
                            if active {
                                Circle().fill(S.accent(scheme)).padding(DS.xs)
                                    .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                            }
                        }.frame(width: DS.lg, height: DS.lg)
                    SettingsIconTile(icon: provider == .chatgpt ? "chat-circle-dots" : provider == .claude ? "sparkle" : "power", selected: active)
                    VStack(alignment: .leading, spacing: DS.xs) {
                        Text(provider?.title ?? "Off").font(S.label)
                        Text(provider.map { "Uses your \($0.title) plan through \($0.toolName) on this Mac" } ?? "Hide Ask everywhere")
                            .font(S.detail).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: DS.sm)
                    if let provider {
                        Text(version(for: provider, state: state)).font(S.mono).foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }.frame(minHeight: compact ? S.compactHeight : S.rowHeight)
            }
            .buttonStyle(SettingsButtonStyle(kind: .plain))
            .accessibilityAddTraits(active ? .isSelected : [])
            if let provider, state == .notInstalled {
                let hint = provider == .chatgpt ? "npm i -g @openai/codex" : "https://claude.com/claude-code"
                HStack(spacing: DS.sm) {
                    if provider == .claude, let url = URL(string: hint) {
                        Button { _ = NSWorkspace.shared.open(url) } label: {
                            HStack(spacing: DS.xs) {
                                Text("Get Claude Code").font(S.detail)
                                Icon("arrow-square-out", size: DS.md)
                            }
                        }
                        .buttonStyle(SettingsButtonStyle(kind: .plain))
                        .accessibilityAddTraits(.isLink).help(hint)
                    } else {
                        Text(hint).font(S.mono).textSelection(.enabled)
                    }
                    Spacer()
                    Button(provider == .chatgpt ? "Copy command" : "Copy link") {
                        AssistantInstallHint.copy(hint, to: .general)
                    }.buttonStyle(SettingsButtonStyle())
                }.padding(DS.sm)
                    .background(S.fill(scheme), in: RoundedRectangle(cornerRadius: S.controlRadius))
            }
        }
    }

    private func version(for provider: AssistantProvider, state: AssistantAvailability?) -> String {
        switch state {
        case .notInstalled: "Not installed"
        case .ready(let account): "\(provider.toolName) \(account.toolVersion)"
        case .signedOut(let version, _), .unsupportedVersion(let version, _): "\(provider.toolName) \(version)"
        case nil: "Checking…"
        }
    }
}

enum AssistantInstallHint {
    @MainActor static func copy(_ hint: String, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.setString(hint, forType: .string)
    }
}

private struct AssistantAccountSettings: View {
    enum Operation { case refresh, signIn, signOut }
    struct Request { let operation: Operation; let id = UUID() }
    let service: any AssistantService
    @Binding var availability: AssistantAvailability?
    @Binding var model: String?
    @LocalState private var request = Request(operation: .refresh)
    @LocalState private var usage: AssistantUsage?
    @LocalState private var models: [String] = []
    @LocalState private var busy = false
    @LocalState private var waiting = false
    @LocalState private var message: String?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        SettingsGroup(title: "Account", index: 1) {
            switch availability {
            case .ready(let account):
                SettingsRow(account.email.map { "Signed in as \($0)" } ?? "Signed in", [service.provider.title, account.plan].compactMap { $0 }.joined(separator: " ")) {
                    Button("Sign out") { begin(.signOut) }.buttonStyle(SettingsButtonStyle()).disabled(busy)
                }
                SettingsDivider()
                SettingsRow("Plan usage", usage?.resetsAt.map { "Resets \($0.formatted(.dateTime.weekday(.wide)))" }) {
                    if let fraction = usage?.usedFraction, fraction.isFinite {
                        let value = min(max(fraction, 0), 1)
                        HStack(spacing: DS.sm) {
                            Text(value.formatted(.percent.precision(.fractionLength(0)))).font(S.mono)
                            Capsule().fill(S.fill(scheme))
                                .overlay(alignment: .leading) { Capsule().fill(S.accent(scheme)).frame(width: S.meterWidth * value) }
                                .frame(width: S.meterWidth, height: DS.xs)
                        }.accessibilityElement(children: .combine)
                    } else {
                        Text(usage?.limitReached == true ? "Limit reached" : "Unavailable").font(S.detail).foregroundStyle(.secondary)
                    }
                }
                SettingsDivider()
                SettingsRow("Model") {
                    SettingsMenu(label: "Assistant model", options: [(nil as String?, "Default")] + modelOptions.map { (Optional($0), $0) },
                                 selection: $model)
                }
            case .signedOut:
                if waiting {
                    SettingsRow("Waiting for your browser…", "Finish signing in and return here.") {
                        Button("Cancel") { begin(.refresh) }.buttonStyle(SettingsButtonStyle())
                    }
                } else {
                    SettingsRow("Signed out", "Continue with your \(service.provider.title) account.") {
                        Button("Sign in with \(service.provider.title)") { begin(.signIn) }
                            .buttonStyle(SettingsButtonStyle()).disabled(busy)
                    }
                }
            case .notInstalled:
                checkAgain("Install \(service.provider.toolName) to sign in.")
            case .unsupportedVersion(_, let minimum):
                checkAgain("Update \(service.provider.toolName) to \(minimum) or later.")
            case nil:
                Text("Checking \(service.provider.toolName)…").font(S.detail).foregroundStyle(.secondary)
            }
            if let message {
                SettingsDivider()
                Text(message).font(S.detail).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }.task(id: request.id) { await run(request.operation) }
    }

    private var modelOptions: [String] {
        var seen = Set<String>()
        return (models + [model].compactMap { $0 }).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private func checkAgain(_ detail: String) -> some View {
        SettingsRow("Setup required", detail) {
            Button("Check again") { begin(.refresh) }.buttonStyle(SettingsButtonStyle()).disabled(busy)
        }
    }

    private func begin(_ operation: Operation) {
        busy = true
        request = Request(operation: operation)
    }

    private func run(_ operation: Operation) async {
        busy = true
        waiting = false
        message = nil
        defer { if !Task.isCancelled { busy = false; waiting = false } }
        do {
            let state: AssistantAvailability
            switch operation {
            case .refresh:
                state = await service.availability()
            case .signOut:
                try await service.signOut()
                try Task.checkCancellation()
                state = await service.availability()
            case .signIn:
                state = try await AssistantAccountFlow.signIn(using: service) { waiting = true }
            }
            try Task.checkCancellation()
            availability = state
            if state.isReady {
                async let used = service.usage()
                async let available = service.models()
                let details = await (used, available)
                try Task.checkCancellation()
                usage = details.0
                models = details.1
            }
        } catch {
            if !Task.isCancelled { message = error.localizedDescription }
        }
    }
}

private struct SuggestionSettings: View {
    @Binding var suggestions: [String]
    @LocalState private var draft = ""
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.sm) {
            SettingsRow("Suggestions", "Drag to reorder the prompts for a new conversation.") {
                Button("Reset to defaults") { change { suggestions = AssistantPreferences.defaultSuggestions } }
                    .buttonStyle(SettingsButtonStyle())
            }
            SettingsFlow(spacing: DS.sm) {
                ForEach(suggestions, id: \.self) { item in
                    HStack(spacing: DS.xs) {
                        Icon("dots-six-vertical", size: DS.md)
                        Text(item).font(S.detail).fixedSize(horizontal: false, vertical: true)
                        Button { change { suggestions.removeAll { $0 == item } } } label: { Icon("x", size: DS.md) }
                            .buttonStyle(SettingsButtonStyle(kind: .plain)).accessibilityLabel("Remove \(item)")
                    }
                    .padding(.horizontal, DS.sm)
                    .background(S.fill(scheme), in: Capsule())
                    .draggable(item)
                    .dropDestination(for: String.self) { dropped, _ in
                        guard let source = dropped.first, suggestions.contains(source) else { return false }
                        change { suggestions = movingItem(source, to: item, in: suggestions) }
                        return true
                    }
                    .modifier(SettingsMoveActions(item: item, items: suggestions) { target in
                        change { suggestions = movingItem(item, to: target, in: suggestions) }
                    })
                    .transition(DS.Motion.pop(reduceMotion: reduceMotion))
                }
            }.id(reduceMotion ? suggestions : nil).transition(.opacity)
            HStack(spacing: DS.sm) {
                TextField("New suggestion", text: $draft).modifier(SettingsField()).onSubmit(add)
                Button("Add", action: add).buttonStyle(SettingsButtonStyle()).disabled(trimmed.isEmpty || suggestions.contains(trimmed))
            }
        }
    }

    private func add() {
        guard !trimmed.isEmpty, !suggestions.contains(trimmed) else { return }
        change { suggestions.append(trimmed); draft = "" }
    }

    private func change(_ edit: () -> Void) {
        withAnimation(DS.Motion.snappy(reduceMotion), edit)
    }
}
