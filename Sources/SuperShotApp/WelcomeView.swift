import SwiftUI
import DesignSystem
import Settings
import Capture

/// A single setup window carries the same sample image from the introduction through the real permission step.
struct WelcomeView: View {
    static let preferredSize = CGSize(width: 780, height: 520)

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @LocalState private var step: WelcomeStep
    @LocalState private var selection: CGRect?
    let settings: SettingsStore
    let permission: ScreenPermission
    let capture: (String) -> Void
    let openSettings: () -> Void
    let openPrivacy: () -> Void
    let finish: () -> Void

    init(settings: SettingsStore, permission: ScreenPermission, capture: @escaping (String) -> Void,
         openSettings: @escaping () -> Void, openPrivacy: @escaping () -> Void, finish: @escaping () -> Void,
         startAt: WelcomeStep = .intro, sampleSelected: Bool = false) {
        self.settings = settings
        self.permission = permission
        self.capture = capture
        self.openSettings = openSettings
        self.openPrivacy = openPrivacy
        self.finish = finish
        _step = LocalState(wrappedValue: startAt)
        _selection = LocalState(wrappedValue: sampleSelected ? WelcomeSelection.example : nil)
    }

    private typealias S = DS.Preferences
    private var ready: Bool { permission.state == .authorized }
    private var heading: String {
        switch step {
        case .intro: "Take your first screenshot"
        case .practice: "Try a selection"
        case .access: ready ? "Ready to capture" : "Allow screen access"
        }
    }
    private var explanation: String {
        switch step {
        case .intro: "Select an area, then copy it, mark it up, pin it, or ask about what you see."
        case .practice: "Drag across the sample image to select a region. You can also use the example selection."
        case .access:
            if ready {
                "Pick an area on your screen. SuperShot closes this window before the selection appears."
            } else if permission.hasRequested {
                "Turn on SuperShot, then return here. If macOS asks, quit and reopen SuperShot."
            } else {
                "macOS requires permission to take screenshots. SuperShot takes a screenshot when you use a capture command."
            }
        }
    }

    var body: some View {
        GeometryReader { bounds in
            let compact = bounds.size.width < 640
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.lg) {
                        header
                        let layout = compact
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.lg))
                            : AnyLayout(HStackLayout(alignment: .center, spacing: DS.xxl))
                        layout {
                            instructions
                                .frame(width: compact ? nil : 252)
                                .frame(maxWidth: compact ? .infinity : 252, alignment: .leading)
                            WelcomePracticeView(step: step, selection: $selection, compact: compact)
                                .frame(maxWidth: .infinity)
                                .layoutPriority(1)
                        }
                    }
                    .padding(.horizontal, compact ? DS.lg : DS.xl)
                    .padding(.top, S.titlebarInset)
                    .padding(.bottom, DS.lg)
                    .frame(maxWidth: 940)
                    .frame(maxWidth: .infinity)
                    .id("setup-content")
                }
                .scrollBounceBehavior(.basedOnSize)
                .onChange(of: step) { _, _ in
                    withAnimation(reduceMotion ? nil : DS.Motion.gentle(false)) {
                        scroll.scrollTo("setup-content", anchor: .top)
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    footer
                        .padding(.horizontal, compact ? DS.lg : DS.xl)
                        .padding(.bottom, DS.lg)
                        .frame(maxWidth: 940)
                        .frame(maxWidth: .infinity)
                        .background(S.canvas(scheme))
                }
            }
        }
        .background { WorkspaceBackground() }
        .ignoresSafeArea()
        .task(id: step) {
            guard step == .access, !DS.rendersOffscreen else { return }
            while !Task.isCancelled {
                permission.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private var header: some View {
        HStack(spacing: DS.sm) {
            BrandIcon(size: DS.xl).accessibilityHidden(true)
            Text("SuperShot").font(DS.emphasis)
            Spacer(minLength: DS.sm)
            HStack(spacing: DS.sm) {
                ForEach(WelcomeStep.allCases, id: \.self) { item in
                    if item != .intro { Icon("caret-right", size: DS.sm).foregroundStyle(.tertiary) }
                    Text(item.name)
                        .font(DS.caption)
                        .foregroundStyle(item == step ? .primary : .secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(step.name), step \(step.rawValue + 1) of \(WelcomeStep.allCases.count)")
        }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: DS.md) {
            Text(heading).font(DS.hero).tracking(DS.heroTracking)
                .accessibilityAddTraits(.isHeader)
                .fixedSize(horizontal: false, vertical: true)
            Text(explanation)
                .font(DS.body)
                .lineSpacing(DS.lineSpacing)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            detail
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(heading)
        .transition(DS.Motion.reveal(from: .trailing, reduceMotion: reduceMotion))
        .animation(DS.Motion.gentle(reduceMotion), value: heading)
    }

    @ViewBuilder private var detail: some View {
        switch step {
        case .intro:
            note("SuperShot lives in your menu bar. Setup works without an account.", icon: "monitor")
        case .practice:
            note("Practice only. This sample doesn’t read your screen or save a file.", icon: "shield-check")
        case .access:
            if ready {
                if let shortcut = settings.preferences.shortcuts["area"]?.display, !shortcut.isEmpty {
                    HStack(spacing: DS.sm) {
                        Icon("keyboard", size: DS.iconSize).accessibilityHidden(true)
                        Text("Capture Area").font(DS.caption)
                        Spacer(minLength: DS.xs)
                        Text(shortcut).font(DS.mono).padding(.horizontal, DS.sm).padding(.vertical, DS.xs)
                            .background(S.selection(scheme), in: RoundedRectangle(cornerRadius: S.controlRadius))
                    }
                    .padding(DS.sm)
                    .background(S.groupFallback(scheme), in: RoundedRectangle(cornerRadius: S.radius))
                    .overlay(RoundedRectangle(cornerRadius: S.radius).strokeBorder(S.edge(scheme), lineWidth: S.hairline))
                    .accessibilityElement(children: .combine)
                } else {
                    note("You can also choose Capture Area from the menu bar.", icon: "keyboard")
                }
            } else {
                note("System Settings → Privacy & Security → Screen & System Audio Recording", icon: "shield-warning")
            }
        }
    }

    private func note(_ title: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: DS.sm) {
            Icon(icon, size: DS.iconSize).accessibilityHidden(true)
            Text(title).font(DS.caption).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.secondary)
    }

    private var footer: some View {
        let access = WelcomeAccessAction(permission)
        return VStack(spacing: DS.md) {
            Rectangle().fill(S.edge(scheme)).frame(height: DS.stroke)
            HStack(spacing: DS.sm) {
                if let previous = step.previous {
                    Button("Back") { go(to: previous) }.setupButton()
                }
                Spacer(minLength: 0)
                secondaryAction
                Button(primaryLabel(access)) { primaryAction(access) }
                    .setupButton(primary: true)
                    .keyboardShortcut(.defaultAction)
                    .layoutPriority(1)
            }
        }
    }

    @ViewBuilder private var secondaryAction: some View {
        switch step {
        case .intro:
            Button("Set up later", action: finish).setupButton()
        case .practice:
            if selection == nil {
                Button("Skip practice", action: advance).setupButton()
            }
        case .access:
            if ready {
                Button("Settings") {
                    finish()
                    openSettings()
                }.setupButton()
                Button("Done", action: finish).setupButton()
            } else {
                Button("Set up later", action: finish).setupButton()
            }
        }
    }

    private func primaryLabel(_ access: WelcomeAccessAction) -> String {
        switch step {
        case .intro: "Get started"
        case .practice: selection == nil ? "Use example" : "Continue"
        case .access: access.label
        }
    }

    private func primaryAction(_ access: WelcomeAccessAction) {
        switch step {
        case .intro:
            advance()
        case .practice:
            if selection == nil {
                withAnimation(DS.Motion.snappy(reduceMotion)) { selection = WelcomeSelection.example }
            } else {
                advance()
            }
        case .access:
            access.perform(permission: permission, openPrivacy: openPrivacy, finish: finish) { capture("area") }
        }
    }

    private func advance() {
        if let next = step.next { go(to: next) }
    }

    private func go(to step: WelcomeStep) {
        withAnimation(DS.Motion.panel(reduceMotion)) { self.step = step }
    }
}
