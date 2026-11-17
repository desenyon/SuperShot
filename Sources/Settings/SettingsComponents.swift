import AppKit
import SwiftUI
import DesignSystem

private typealias S = DS.Preferences

private struct SettingsAccessibilityPreviewKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var settingsAccessibilityPreview: Bool {
        get { self[SettingsAccessibilityPreviewKey.self] }
        set { self[SettingsAccessibilityPreviewKey.self] = newValue }
    }
}
public extension View {
    /// Exercises accessibility fallbacks without changing the user's macOS preferences.
    func settingsAccessibilityPreview() -> some View { environment(\.settingsAccessibilityPreview, true) }
}

/// Native materials on screen; opaque, appearance-specific colors only for accessibility
/// and offscreen snapshots, where there is no WindowServer backdrop to sample.
struct SettingsSurface: View {
    enum Role { case sidebar, group }
    let role: Role
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.settingsAccessibilityPreview) private var accessibilityPreview
    var body: some View {
        Group {
            if reduceTransparency || accessibilityPreview || DS.rendersOffscreen {
                role == .sidebar ? S.sidebarFallback(scheme) : S.groupFallback(scheme)
            } else if role == .sidebar {
                SidebarMaterial()
            } else {
                Rectangle().fill(.regularMaterial)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct SettingsGroup<Content: View>: View {
    let title: String?
    var footer: String?
    @ViewBuilder var content: () -> Content
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.settingsAccessibilityPreview) private var accessibilityPreview
    var body: some View {
        VStack(alignment: .leading, spacing: DS.sm) {
            if let title {
                Text(title).font(S.section).foregroundStyle(.secondary)
                    .padding(.leading, DS.xs).accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 0, content: content)
                .padding(S.groupInset).frame(maxWidth: .infinity, alignment: .leading)
                .background(SettingsSurface(role: .group))
                .clipShape(RoundedRectangle(cornerRadius: S.radius))
                .overlay(RoundedRectangle(cornerRadius: S.radius).strokeBorder(contrast == .increased || accessibilityPreview ? S.accent(scheme) : S.edge(scheme), lineWidth: S.hairline))
            if let footer {
                Text(footer).font(S.detail).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, DS.xs)
            }
        }
    }
}

/// All Settings buttons retain native activation and keyboard traversal, with a neutral
/// visible focus outline instead of inheriting the editor's indigo accent.
struct SettingsButtonStyle: PrimitiveButtonStyle {
    enum Kind { case standard, plain, choice(Bool), navigation(Bool), segment(Bool) }
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
        private var inset: CGFloat { if case .standard = kind { DS.sm } else { 0 } }
        private var fill: Color {
            switch kind {
            case .standard: hovering ? S.selection(scheme) : S.fill(scheme)
            case .plain: hovering ? S.fill(scheme) : .clear
            case .choice(let selected), .navigation(let selected): selected ? S.selection(scheme) : (hovering ? S.fill(scheme) : .clear)
            case .segment(let selected): selected ? S.raised(scheme) : (hovering ? S.fill(scheme) : .clear)
            }
        }
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(S.detail).foregroundStyle(Color.primary)
                .padding(.horizontal, inset).frame(minHeight: S.controlHeight)
                .contentShape(RoundedRectangle(cornerRadius: S.controlRadius))
                .background(fill, in: RoundedRectangle(cornerRadius: S.controlRadius))
                .overlay(RoundedRectangle(cornerRadius: S.controlRadius)
                    .strokeBorder(focused ? S.accent(scheme) : .clear, lineWidth: S.focusWidth))
                .opacity(enabled ? (configuration.isPressed ? 0.65 : 1) : 0.4)
        }
    }
}

struct SettingsSegments<Value: Hashable>: View {
    let options: [(Value, String)]
    let selection: Value
    let select: (Value) -> Void
    @Environment(\.colorScheme) private var scheme
    init(_ options: [(Value, String)], selection: Value, select: @escaping (Value) -> Void) {
        self.options = options; self.selection = selection; self.select = select
    }
    var body: some View {
        HStack(spacing: DS.xs / 2) {
            ForEach(options, id: \.0) { value, title in
                Button { select(value) } label: {
                    Text(title).font(S.detail).lineLimit(1).frame(maxWidth: .infinity)
                }
                .buttonStyle(SettingsButtonStyle(kind: .segment(selection == value)))
                .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
        .padding(DS.xs / 2)
        .background(S.fill(scheme), in: RoundedRectangle(cornerRadius: S.controlRadius + DS.xs / 2))
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
                    Circle().fill(Color.white)
                        .frame(width: S.switchThumb, height: S.switchThumb).padding(DS.xs / 2)
                }
                .frame(width: S.switchSize.width, height: S.switchSize.height)
                .padding(.horizontal, DS.xs)
        }
        .buttonStyle(SettingsButtonStyle(kind: .plain))
        .animation(DS.quick(reduceMotion: reduceMotion), value: isOn)
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
    @LocalState private var draft: Double?
    @LocalState private var editing = false
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme
    init(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String = "", percent: Bool = false) {
        self.title = title; _value = value; self.range = range; self.unit = unit; self.percent = percent
    }
    private func normalized(_ number: Double) -> Double { percent ? number : number.rounded() }
    private var display: String {
        let number = draft ?? value
        return percent ? "\(Int((number * 100).rounded()))%" : "\(Int(number.rounded())) \(unit)"
    }
    var body: some View {
        HStack(spacing: DS.md) {
            Text(title).font(S.label).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DS.sm)
            HStack(spacing: DS.sm) {
                Slider(value: Binding(get: { draft ?? value }, set: { next in
                    if editing { draft = next } else { value = normalized(next) }
                }), in: range, onEditingChanged: { active in
                    editing = active
                    if !active, let draft { value = normalized(draft); self.draft = nil }
                }) { Text(title) }
                    .labelsHidden().tint(S.accent(scheme))
                    .focused($focused).focusEffectDisabled()
                    .overlay(RoundedRectangle(cornerRadius: S.controlRadius).strokeBorder(focused ? S.accent(scheme) : .clear, lineWidth: S.focusWidth))
                Text(display).font(S.mono).foregroundStyle(.secondary).frame(width: 46, alignment: .trailing)
                    .accessibilityHidden(true)
            }.frame(width: S.controlWidth)
        }.frame(minHeight: S.rowHeight)
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
                .strokeBorder(focused ? S.accent(scheme) : S.edge(scheme), lineWidth: focused ? S.focusWidth : S.hairline))
    }
}

struct SettingsMenu<Value: Hashable>: View {
    let label: String
    let options: [(Value, String)]
    @Binding var selection: Value
    var body: some View {
        NativeSettingsMenu(label: label, options: options, selection: $selection)
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
        super.draw(dirtyRect)
        if window?.firstResponder === self {
            S.nsFocus.setStroke()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: DS.xs / 2, dy: DS.xs / 2), xRadius: S.controlRadius, yRadius: S.controlRadius)
            path.lineWidth = S.focusWidth; path.stroke()
        }
    }
}
