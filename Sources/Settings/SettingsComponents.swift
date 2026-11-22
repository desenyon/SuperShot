import AppKit
import SwiftUI
import DesignSystem

private typealias S = DS.Preferences

private struct SettingsAccessibilityPreviewKey: EnvironmentKey { static let defaultValue = false }
private struct SettingsCompactKey: EnvironmentKey { static let defaultValue = false }
private struct SettingsEditingPreviewKey: EnvironmentKey { static let defaultValue = false }
private struct SettingsFirstVisitKey: EnvironmentKey { static let defaultValue = true }
private struct SettingsSidebarPreviewKey: EnvironmentKey {
    static let defaultValue: (collapsed: Bool, query: String?) = (false, nil)
}
extension EnvironmentValues {
    var settingsEditingPreview: Bool {
        get { self[SettingsEditingPreviewKey.self] }
        set { self[SettingsEditingPreviewKey.self] = newValue }
    }
    var settingsCompact: Bool {
        get { self[SettingsCompactKey.self] }
        set { self[SettingsCompactKey.self] = newValue }
    }
    var settingsFirstVisit: Bool {
        get { self[SettingsFirstVisitKey.self] }
        set { self[SettingsFirstVisitKey.self] = newValue }
    }
    var settingsAccessibilityPreview: Bool {
        get { self[SettingsAccessibilityPreviewKey.self] }
        set { self[SettingsAccessibilityPreviewKey.self] = newValue }
    }
    var settingsSidebarPreview: (collapsed: Bool, query: String?) {
        get { self[SettingsSidebarPreviewKey.self] }
        set { self[SettingsSidebarPreviewKey.self] = newValue }
    }
}
public extension View {
    /// Setup shares Settings controls, with one accent action for completing the current step.
    func setupButton(primary: Bool = false) -> some View {
        buttonStyle(SettingsButtonStyle(kind: primary ? .setupPrimary : .standard))
    }

    /// Opens the area toolbar editor for offscreen layout inspection.
    func settingsToolbarEditingPreview() -> some View { environment(\.settingsEditingPreview, true) }

    /// Exercises accessibility fallbacks without changing the user's macOS preferences.
    func settingsAccessibilityPreview() -> some View { environment(\.settingsAccessibilityPreview, true) }

    /// Shows the compact rail or search results in an offscreen preview.
    func settingsSidebarPreview(collapsed: Bool = false, query: String? = nil) -> some View {
        environment(\.settingsSidebarPreview, (collapsed, query))
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String?
    var index = 0
    var footer: String?
    @ViewBuilder var content: () -> Content
    @Environment(\.colorScheme) private var scheme
    @Environment(\.settingsFirstVisit) private var firstVisit
    @ViewBuilder var body: some View {
        if firstVisit && !DS.rendersOffscreen { group.staggeredAppear(index) } else { group }
    }
    private var group: some View {
        VStack(alignment: .leading, spacing: DS.sm) {
            if let title {
                Text(title).font(S.navigation).foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                Rectangle().fill(S.edge(scheme)).frame(height: S.hairline)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 0, content: content)
                .padding(.vertical, S.groupInset).frame(maxWidth: .infinity, alignment: .leading)
            if let footer {
                Text(footer).font(S.detail).foregroundStyle(.secondary)
                    .frame(maxWidth: S.helpWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Retains native button activation with one focus outline for keyboard traversal.
struct SettingsButtonStyle: PrimitiveButtonStyle {
    enum Kind: Equatable { case standard, plain, choice(Bool), setupPrimary, sidebar }
    var kind: Kind = .standard
    func makeBody(configuration: Configuration) -> some View { StyledButton(configuration: configuration, kind: kind) }
    private struct StyledButton: View {
        let configuration: Configuration
        let kind: Kind
        @FocusState private var focused: Bool
        @LocalState private var hovering = false
        var body: some View {
            Button(action: configuration.trigger) { configuration.label }
                .buttonStyle(Appearance(kind: kind, focused: focused, hovering: hovering))
                .focused($focused).focusEffectDisabled()
                .onHover { hovering = $0 }
        }
    }
    private struct Appearance: ButtonStyle {
        let kind: Kind
        let focused: Bool
        let hovering: Bool
        @Environment(\.colorScheme) private var scheme
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        private var inset: CGFloat {
            switch kind {
            case .setupPrimary: DS.md
            case .standard: DS.sm
            default: 0
            }
        }
        private var fill: Color {
            switch kind {
            case .setupPrimary: DS.accent.opacity(hovering ? 0.9 : 1)
            case .standard: hovering ? S.selection(scheme) : S.fill(scheme)
            case .plain: hovering ? S.fill(scheme) : .clear
            case .sidebar: hovering ? S.sidebarTile : .clear
            case .choice(let selected): selected ? S.selection(scheme) : (hovering ? S.fill(scheme) : .clear)
            }
        }
        private var outline: Color {
            if focused { return kind == .sidebar ? S.sidebarFocus : S.accent(scheme) }
            switch kind {
            case .standard, .choice(true): return S.controlEdge(scheme)
            case .plain, .choice(false), .setupPrimary, .sidebar: return .clear
            }
        }
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(kind == .setupPrimary ? S.navigation : S.detail)
                .foregroundStyle(kind == .setupPrimary ? DS.onAccent : Color.primary)
                .padding(.horizontal, inset).frame(minHeight: S.controlHeight)
                .contentShape(RoundedRectangle(cornerRadius: S.controlRadius))
                .background(fill, in: RoundedRectangle(cornerRadius: S.controlRadius))
                .overlay(RoundedRectangle(cornerRadius: S.controlRadius)
                    .strokeBorder(outline, lineWidth: focused ? S.focusWidth : S.hairline))
                .animation(DS.Motion.hover(reduceMotion), value: hovering)
                .opacity(enabled ? (configuration.isPressed ? 0.65 : 1) : 0.4)
        }
    }
}

struct SettingsSegments<Value: Hashable>: View {
    let options: [(Value, String)]
    let selection: Value
    let select: (Value) -> Void
    @Environment(\.colorScheme) private var scheme
    @Namespace private var indicator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(_ options: [(Value, String)], selection: Value, select: @escaping (Value) -> Void) {
        self.options = options; self.selection = selection; self.select = select
    }
    var body: some View {
        HStack(spacing: DS.xs / 2) {
            ForEach(options, id: \.0) { value, title in
                Button { select(value) } label: {
                    Text(title).font(selection == value ? S.detail.weight(.semibold) : S.detail)
                        .lineLimit(1).frame(maxWidth: .infinity)
                        .frame(height: S.controlHeight - DS.xs)
                        .background {
                            if selection == value {
                                let shape = RoundedRectangle(cornerRadius: S.controlRadius).fill(S.raised(scheme))
                                    .overlay(RoundedRectangle(cornerRadius: S.controlRadius).strokeBorder(S.controlEdge(scheme), lineWidth: S.hairline))
                                if reduceMotion { shape.transition(.opacity) }
                                else { shape.matchedGeometryEffect(id: "selected", in: indicator) }
                            }
                        }
                }
                .buttonStyle(SettingsButtonStyle(kind: .plain))
                .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
        .animation(DS.Motion.snappy(reduceMotion), value: selection)
        .padding(.horizontal, DS.xs / 2)
        .background(S.fill(scheme), in: RoundedRectangle(cornerRadius: S.controlRadius + DS.xs / 2))
        .overlay(RoundedRectangle(cornerRadius: S.controlRadius + DS.xs / 2)
            .strokeBorder(S.edge(scheme), lineWidth: S.hairline).allowsHitTesting(false))
    }
}

struct SettingsToggle: View {
    let label: String
    @Binding var isOn: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Button { isOn.toggle() } label: {
            Capsule().fill(S.switchTrack(on: isOn, scheme: scheme))
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle().fill(DS.white).id(reduceMotion ? isOn : false).transition(.opacity)
                        .frame(width: S.switchThumb, height: S.switchThumb).padding(DS.xs / 2)
                }
                .frame(width: S.switchSize.width, height: S.switchSize.height)
                .padding(.horizontal, DS.xs)
        }
        .buttonStyle(SettingsButtonStyle(kind: .plain))
        .animation(DS.Motion.snappy(reduceMotion), value: isOn)
        .accessibilityRepresentation {
            Toggle(label, isOn: $isOn).toggleStyle(.switch)
        }
    }
}

/// Uses the platform slider for native arrow keys, pointer tracking, and VoiceOver.
/// Mouse drags remain local drafts; only the final value is persisted.
struct PreferenceSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var unit = ""
    var percent = false
    private let defaultLabel: String?
    private let onPreview: ((Double?) -> Void)?
    @LocalState private var draft: Double?
    @LocalState private var editing = false
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme
    init(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String = "", percent: Bool = false,
         defaultLabel: String? = nil,
         onPreview: ((Double?) -> Void)? = nil) {
        self.title = title; _value = value; self.range = range; self.unit = unit; self.percent = percent
        self.defaultLabel = defaultLabel
        self.onPreview = onPreview
    }
    @Environment(\.settingsCompact) private var compact
    private func normalized(_ number: Double) -> Double { percent ? number : number.rounded() }
    private var display: String {
        if draft == nil, let defaultLabel { return defaultLabel }
        let number = draft ?? value
        return percent ? "\(Int((number * 100).rounded()))%" : "\(Int(number.rounded())) \(unit)"
    }
    var body: some View {
        HStack(spacing: DS.md) {
            Text(title).font(S.label).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DS.sm)
            HStack(spacing: DS.sm) {
                Slider(value: Binding(get: { draft ?? value }, set: { next in
                    if editing {
                        draft = next
                        onPreview?(next)
                    } else { value = normalized(next) }
                }), in: range, onEditingChanged: { active in
                    editing = active
                    if !active, let draft { value = normalized(draft); self.draft = nil }
                    if !active { onPreview?(nil) }
                }) { Text(title) }
                    .labelsHidden().tint(S.accent(scheme))
                    .focused($focused).focusEffectDisabled()
                    .overlay(RoundedRectangle(cornerRadius: S.controlRadius).strokeBorder(focused ? S.accent(scheme) : .clear, lineWidth: S.focusWidth))
                Text(display).font(S.mono).foregroundStyle(.secondary).frame(width: S.sliderValueWidth, alignment: .trailing)
                    .accessibilityHidden(true)
            }.frame(width: S.controlWidth)
        }.frame(minHeight: compact ? S.compactHeight : S.rowHeight).modifier(SettingsRowHover())
    }
}

struct SettingsField: ViewModifier {
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.textFieldStyle(.plain).font(S.mono)
            .padding(.horizontal, DS.sm).frame(minHeight: S.controlHeight)
            .background(S.fill(scheme), in: RoundedRectangle(cornerRadius: S.controlRadius))
            .focused($focused).focusEffectDisabled()
            .overlay(RoundedRectangle(cornerRadius: S.controlRadius)
                .strokeBorder(focused ? S.accent(scheme) : S.controlEdge(scheme), lineWidth: focused ? S.focusWidth : S.hairline))
    }
}

struct SettingsMenu<Value: Hashable>: View {
    let label: String
    let options: [(Value, String)]
    @Binding var selection: Value
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        ZStack {
            HStack(spacing: DS.sm) {
                Text(options.first { $0.0 == selection }?.1 ?? "Choose…").font(S.detail).lineLimit(1)
                Spacer(minLength: 0)
                Icon("caret-up-down", size: DS.md)
            }
            .padding(.horizontal, DS.sm)
            .frame(height: S.controlHeight)
            .background(S.fill(scheme), in: RoundedRectangle(cornerRadius: S.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: S.controlRadius).strokeBorder(S.controlEdge(scheme), lineWidth: S.hairline))
            .opacity(enabled ? 1 : DS.mutedOpacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            NativeSettingsMenu(label: label, options: options, selection: $selection)
        }
        .frame(width: S.controlWidth, height: S.controlHeight)
    }
}

/// A real popup button keeps its entire bezel on the control grid. SwiftUI's menu
/// style otherwise collapses a custom label to its intrinsic width on macOS.
private struct NativeSettingsMenu<Value: Hashable>: NSViewRepresentable {
    let label: String
    let options: [(Value, String)]
    @Binding var selection: Value
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> SettingsPopUpButton {
        let button = SettingsPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .small
        button.font = .systemFont(ofSize: 11)
        button.bezelStyle = .rounded
        button.bezelColor = .controlColor
        button.contentTintColor = .labelColor
        button.focusRingType = .none
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.target = context.coordinator
        button.action = #selector(Coordinator.select(_:))
        return button
    }
    func updateNSView(_ button: SettingsPopUpButton, context: Context) {
        if button.itemTitles != options.map(\.1) {
            button.removeAllItems(); button.addItems(withTitles: options.map(\.1))
        }
        button.selectItem(at: options.firstIndex { $0.0 == selection } ?? -1)
        button.isEnabled = context.environment.isEnabled
        button.setAccessibilityLabel(label)
        context.coordinator.changed = { index in
            guard options.indices.contains(index) else { return }
            selection = options[index].0
        }
    }
    @MainActor final class Coordinator: NSObject {
        var changed: ((Int) -> Void)?
        @objc func select(_ sender: NSPopUpButton) { changed?(sender.indexOfSelectedItem) }
    }
}

private final class SettingsPopUpButton: NSPopUpButton {
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        DispatchQueue.main.async { [weak self] in self?.needsDisplay = true }
        return result
    }
    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        DispatchQueue.main.async { [weak self] in self?.needsDisplay = true }
        return result
    }
    override func draw(_ dirtyRect: NSRect) {
        // SwiftUI draws the label and bezel. The popup retains native menu and keyboard handling.
        if window?.firstResponder === self {
            S.nsFocus.setStroke()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: DS.xs / 2, dy: DS.xs / 2), xRadius: S.controlRadius, yRadius: S.controlRadius)
            path.lineWidth = S.focusWidth; path.stroke()
        }
    }
}


struct SettingsRow<Control: View>: View {
    let title: String
    let detail: String?
    let detailLines: Int?
    @ViewBuilder let control: () -> Control

    @Environment(\.settingsCompact) private var compact
    init(_ title: String, _ detail: String? = nil, detailLines: Int? = nil, @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.detail = detail
        self.detailLines = detailLines
        self.control = control
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: DS.xs) {
            Text(title).font(S.label).fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail).font(S.detail).foregroundStyle(.secondary)
                    .lineLimit(detailLines).truncationMode(.middle).fixedSize(horizontal: false, vertical: true).help(detail)
                    .frame(maxWidth: S.helpWidth, alignment: .leading)
            }
        }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.md) {
                label.frame(minWidth: S.rowLabelWidth, idealWidth: S.rowLabelWidth, maxWidth: .infinity, alignment: .leading)
                control().fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: DS.sm) {
                label
                control()
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, compact ? DS.xs / 2 : DS.xs)
        .frame(minHeight: compact ? S.compactHeight : S.rowHeight)
        .modifier(SettingsRowHover())
    }
}

struct SettingsDivider: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Rectangle().fill(S.edge(scheme)).frame(height: S.hairline)
            .accessibilityHidden(true)
    }
}

/// Wraps chips and toolbar previews without clipping longer labels in narrow windows.
struct SettingsFlow: Layout {
    let spacing: CGFloat

    private func arrangement(_ subviews: Subviews, width: CGFloat) -> (origins: [CGPoint], size: CGSize) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, usedWidth: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: width.isFinite ? width : nil, height: nil))
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            usedWidth = max(usedWidth, x + size.width)
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return (origins, CGSize(width: usedWidth, height: y + lineHeight))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(subviews, width: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, origin) in zip(subviews, arrangement(subviews, width: bounds.width).origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                          proposal: ProposedViewSize(width: bounds.width, height: nil))
        }
    }
}

struct SettingsMoveActions: ViewModifier {
    let item: String
    let items: [String]
    let move: (String) -> Void

    @ViewBuilder private var actions: some View {
        if let index = items.firstIndex(of: item) {
            if index > 0 { Button("Move up") { move(items[index - 1]) } }
            if index + 1 < items.count { Button("Move down") { move(items[index + 1]) } }
        }
    }

    func body(content: Content) -> some View {
        content.contextMenu { actions }.accessibilityActions { actions }
    }
}

struct SettingsIconTile: View {
    let icon: String
    let selected: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Icon(icon, weight: selected ? .fill : .regular, size: DS.lg)
            .frame(width: S.tile, height: S.tile)
            .background(S.tileFill(scheme, selected: selected), in: RoundedRectangle(cornerRadius: S.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: S.controlRadius).strokeBorder(S.edge(scheme), lineWidth: S.hairline))
            .accessibilityHidden(true)
    }
}

struct SettingsRowHover: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @LocalState private var hovering = false
    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: S.controlRadius).fill(S.fill(scheme))
                .padding(.horizontal, -DS.xs).opacity(hovering ? 1 : 0)
        }.onHover { hovering = $0 }.animation(DS.Motion.hover(reduceMotion), value: hovering)
    }
}
