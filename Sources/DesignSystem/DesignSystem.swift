import SwiftUI
import AppKit

/// Shared tokens. Feature code takes colors, type, spacing, radii, and motion from here.
public enum DS {
    // MARK: Color

    /// The single accent, chosen in Settings → Appearance. Used for selection and primary actions only.
    /// Reading it inside a SwiftUI body subscribes the view to accent changes.
    @MainActor public static var accent: Color { Color(nsColor: nsAccent) }
    /// The accent lifted for text and icons on dark surfaces.
    @MainActor public static var accentBright: Color { Color(nsColor: accentPalette(ThemeState.shared.accent).bright) }
    /// Text and icons drawn on top of an accent fill.
    @MainActor public static var onAccent: Color { Color(nsColor: accentPalette(ThemeState.shared.accent).on) }
    @MainActor public static var nsAccent: NSColor { accentPalette(ThemeState.shared.accent).base }
    public static func accentPalette(_ choice: AccentChoice) -> (base: NSColor, bright: NSColor, on: NSColor) {
        func hex(_ value: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: 1)
        }
        func dynamic(_ light: UInt32, _ dark: UInt32) -> NSColor {
            NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua]) != nil ? hex(dark) : hex(light) }
        }
        switch choice {
        case .blue: return (hex(0x2F7CF6), dynamic(0x1F6AE0, 0x6AA6FF), .white)
        case .teal: return (hex(0x0FA697), dynamic(0x0B8A7D, 0x3FD3C3), .white)
        case .graphite: return (dynamic(0x1C1D21, 0xF1F2F4), dynamic(0x1C1D21, 0xF1F2F4), dynamic(0xFFFFFF, 0x111214))
        case .tangerine: return (hex(0xF26B0F), dynamic(0xD95C06, 0xFF9A52), .white)
        }
    }
    public static let ink = Color(red: 0.09, green: 0.10, blue: 0.13)
    public static let midnight = Color(red: 0.043, green: 0.047, blue: 0.058)
    public static let paper = Color(red: 0.93, green: 0.935, blue: 0.945)
    public static let slate = Color(red: 0.42, green: 0.45, blue: 0.52)
    public static let white = Color.white
    public static let black = Color.black
    public static let danger = Color(red: 1.0, green: 0.36, blue: 0.36)
    public static let success = Color(red: 0.25, green: 0.80, blue: 0.56)

    public static func background(_ scheme: ColorScheme) -> Color { scheme == .dark ? midnight : paper }
    /// Text and icon color for selected and interactive elements.
    @MainActor public static func actionInk(_ scheme: ColorScheme) -> Color { accentBright }
    /// Opaque stand-in for glass, used when Reduce Transparency is on or when rendering offscreen.
    public static func panel(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.105, green: 0.11, blue: 0.13) : Color(red: 0.985, green: 0.985, blue: 0.99)
    }
    /// Grouped-row background inside panels and settings.
    public static func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.04)
    }
    public static func hairline(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.08)
    }
    public static func hover(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.06)
    }

    // MARK: Type (three sizes per surface: title, body, caption)

    public static let hero = Font.system(size: 34, weight: .bold)
    public static let title = Font.system(size: 17, weight: .semibold)
    public static let body = Font.system(size: 13)
    public static let emphasis = Font.system(size: 13, weight: .semibold)
    public static let caption = Font.system(size: 11, weight: .medium)
    public static let mono = Font.system(size: 11, weight: .medium, design: .monospaced).monospacedDigit()
    public static let heroTracking: CGFloat = -0.8
    public static let lineSpacing: CGFloat = 4

    // MARK: Spacing and shape

    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 40
    public static let radius: CGFloat = 20
    public static let smallRadius: CGFloat = 10
    public static let controlRadius: CGFloat = 8
    public static let pill: CGFloat = 100
    public static let stroke: CGFloat = 1
    public static let icon: CGFloat = 15
    /// Phosphor glyphs sit lighter than SF Symbols at the same point size.
    public static let iconSize: CGFloat = 18

    public static let mutedOpacity = 0.55
    public static let subtleOpacity = 0.08
    public static let outlineOpacity = 0.16
    public static let shadowOpacity = 0.28
    public static let shadowRadius: CGFloat = 28
    public static let shadowY: CGFloat = 14

    // MARK: Windows

    public static let windowSize = CGSize(width: 1000, height: 740)
    public static let welcomeSize = CGSize(width: 480, height: 400)
    public static let settingsSize = CGSize(width: 860, height: 640)
    public static let groupRadius: CGFloat = 12
    public static let pinResizeInset: CGFloat = 12
    public static let pinMinimumLongEdge: CGFloat = 160
    public static func settingsBackground(_ scheme: ColorScheme) -> Color { color(scheme == .dark ? 0x1B2025 : 0xF0F1F2) }
    public static func settingsGroup(_ scheme: ColorScheme) -> Color { color(scheme == .dark ? 0x272D33 : 0xFFFFFF) }
    public static let sidebarWidth: CGFloat = 204
    public static let illustrationSize = CGSize(width: 440, height: 380)
    public static let thumbnailSize = CGSize(width: 264, height: 188)
    public static let previewSize = CGSize(width: 960, height: 660)
    public static let editorSize = CGSize(width: 1280, height: 820)
    public static let editorMinimum = CGSize(width: 980, height: 620)

    public static func fittingWindowSize(preferred: CGSize, available: CGSize) -> CGSize {
        CGSize(width: min(preferred.width, max(1, available.width - xxl)),
               height: min(preferred.height, max(1, available.height - xxl)))
    }

    // MARK: Motion

    public static func motionDuration(reduceMotion: Bool) -> Double { reduceMotion ? 0 : 0.28 }
    public static func spring(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)
    }
    public static func quick(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.14)
    }

    // MARK: Editor layout

    public static let edge: CGFloat = 12
    public static let toolButton: CGFloat = 30
    public static let barHeight: CGFloat = 42
    public static let backdropPanelWidth: CGFloat = 264
    public static let sidePanelWidth: CGFloat = 288
    public static let inspectorWidth: CGFloat = 264
    public static let canvasTop: CGFloat = 112
    public static let canvasBottom: CGFloat = 72
    public static let canvasMargin: CGFloat = 40
    public static let selectionHandle: CGFloat = 9

    // MARK: Capture overlay

    public static let overlayDim = 0.42
    public static let overlayLine: CGFloat = 1.5
    public static let loupeSize: CGFloat = 132
    public static let loupePixels: CGFloat = 15
    public static let badgeHeight: CGFloat = 26
    @MainActor public static let overlayFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
    @MainActor public static let hintFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    @MainActor public static var canvasChecker: NSColor { .labelColor.withAlphaComponent(0.05) }

    /// Set by the offscreen preview renderer, where system glass has no backdrop to sample.
    @MainActor public static var rendersOffscreen = false
}

// MARK: - Palettes

public extension DS {
    static let annotationColors: [NSColor] = [
        NSColor(srgbRed: 1.00, green: 0.27, blue: 0.30, alpha: 1),
        NSColor(srgbRed: 1.00, green: 0.58, blue: 0.10, alpha: 1),
        NSColor(srgbRed: 1.00, green: 0.82, blue: 0.16, alpha: 1),
        NSColor(srgbRed: 0.20, green: 0.80, blue: 0.47, alpha: 1),
        NSColor(srgbRed: 0.18, green: 0.56, blue: 1.00, alpha: 1),
        NSColor(srgbRed: 0.07, green: 0.78, blue: 0.80, alpha: 1),
        NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
        NSColor(srgbRed: 0.07, green: 0.07, blue: 0.08, alpha: 1)
    ]

    struct GradientPreset: Identifiable, Sendable {
        public let id: String
        public let name: String
        public let hex: [UInt32]
        public let angle: Double
        public var colors: [Color] { hex.map(DS.color) }
    }

    static let gradients: [GradientPreset] = [
        GradientPreset(id: "lagoon", name: "Lagoon", hex: [0x1F6AE0, 0x22B8C9, 0x9AF2E0], angle: 45),
        GradientPreset(id: "sunset", name: "Sunset", hex: [0xFF5F6D, 0xFF9966, 0xFFC371], angle: 45),
        GradientPreset(id: "ocean", name: "Ocean", hex: [0x1E3CFF, 0x2D9CFF, 0x5CE1E6], angle: 45),
        GradientPreset(id: "mint", name: "Mint", hex: [0x0BA360, 0x3CBA92, 0xB5F0D0], angle: 45),
        GradientPreset(id: "peach", name: "Peach", hex: [0xFF9A8B, 0xFAD0C4, 0xFFE8C7], angle: 45),
        GradientPreset(id: "sky", name: "Sky", hex: [0x4D8DFF, 0x9CC9FF, 0xE8F4FF], angle: 90),
        GradientPreset(id: "ember", name: "Ember", hex: [0x2A0E0A, 0xB3261E, 0xFF8A3D], angle: 45),
        GradientPreset(id: "aurora", name: "Aurora", hex: [0x0F2027, 0x1F6F78, 0x7FFFD4], angle: 60),
        GradientPreset(id: "forest", name: "Forest", hex: [0x0B3D2E, 0x1F7A5A, 0x9BE3B8], angle: 45),
        GradientPreset(id: "sand", name: "Sand", hex: [0xF6EFE3, 0xE6D5BD, 0xCDB592], angle: 45),
        GradientPreset(id: "graphite", name: "Graphite", hex: [0x2A2C31, 0x16171A], angle: 90),
        GradientPreset(id: "cloud", name: "Cloud", hex: [0xFFFFFF, 0xE9ECF2], angle: 90)
    ]

    static let solidHex: [UInt32] = [
        0xFFFFFF, 0xF1F2F4, 0x1C1D21, 0x000000, 0xFF5A5F, 0xFF9F1C,
        0xFFD23F, 0x3DDC97, 0x2EC4B6, 0x2F7CF6, 0x5B6B7F, 0xFF8A65
    ]

    static func color(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
    static func components(_ hex: UInt32) -> (red: Double, green: Double, blue: Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }
    /// Start and end points for a linear gradient at `angle` degrees (0 = left to right, 90 = top to bottom).
    static func gradientPoints(angle: Double) -> (UnitPoint, UnitPoint) {
        let radians = angle * .pi / 180, dx = cos(radians) / 2, dy = sin(radians) / 2
        return (UnitPoint(x: 0.5 - dx, y: 0.5 - dy), UnitPoint(x: 0.5 + dx, y: 0.5 + dy))
    }
}

public typealias LocalState<Value> = SwiftUI.State<Value>

// MARK: - Surfaces

/// Floating chrome. System Liquid Glass on screen, an opaque panel where glass cannot render.
public struct GlassSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let radius: CGFloat
    private let tint: Color?
    private let interactive: Bool
    private let backing: Color?
    private let showsShadow: Bool
    /// `tint` colors the glass itself (for a primary control); `interactive` makes it respond to the pointer.
    public init(radius: CGFloat = DS.radius, tint: Color? = nil, interactive: Bool = false, backing: Color? = nil,
                showsShadow: Bool = true) {
        self.radius = radius; self.tint = tint; self.interactive = interactive; self.backing = backing
        self.showsShadow = showsShadow
    }
    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if DS.usesOpaqueChrome(reduceTransparency: reduceTransparency) {
            content
                .background(tint ?? DS.panel(scheme), in: shape)
                .overlay(shape.strokeBorder(tint == nil ? DS.hairline(scheme) : Color.white.opacity(DS.outlineOpacity), lineWidth: DS.stroke))
                .shadow(color: showsShadow ? .black.opacity(scheme == .dark ? 0.45 : 0.14) : .clear, radius: DS.md, y: DS.xs)
        } else {
            // System glass tints only faintly; a solid tint layer inside the shape keeps primary controls legible on any backdrop.
            content
                .background { if let fill = tint?.opacity(0.9) ?? backing { shape.fill(fill) } }
                .glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        }
    }
}

public extension DS {
    /// Opaque stand-ins replace system glass when the user chose solid chrome, asked for less transparency,
    /// or when rendering offscreen, where glass has nothing to sample.
    @MainActor static func usesOpaqueChrome(reduceTransparency: Bool) -> Bool {
        ThemeState.shared.chrome == .solid || DS.rendersOffscreen || reduceTransparency
    }
}

/// Lets neighbouring glass shapes blend into one another, as system Liquid Glass does in toolbars.
public struct GlassGroup<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let spacing: CGFloat
    private let content: Content
    public init(spacing: CGFloat = DS.sm, @ViewBuilder content: () -> Content) { self.spacing = spacing; self.content = content() }
    public var body: some View {
        if DS.usesOpaqueChrome(reduceTransparency: reduceTransparency) { content }
        else { GlassEffectContainer(spacing: spacing) { content } }
    }
}

/// A grouped block of rows inside a panel or settings page.
public struct Card<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    private let padding: CGFloat
    private let content: Content
    public init(padding: CGFloat = DS.md, @ViewBuilder content: () -> Content) { self.padding = padding; self.content = content() }
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.card(scheme), in: RoundedRectangle(cornerRadius: DS.smallRadius, style: .continuous))
    }
}

public struct Hairline: View {
    @Environment(\.colorScheme) private var scheme
    public init() {}
    public var body: some View { Rectangle().fill(DS.hairline(scheme)).frame(height: DS.stroke) }
}

public struct SectionLabel: View {
    private let title: String
    public init(_ title: String) { self.title = title }
    public var body: some View {
        Text(title).font(DS.caption).foregroundStyle(.secondary)
    }
}

// MARK: - Buttons

public struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(DS.emphasis)
            .padding(.horizontal, DS.lg).frame(height: DS.toolButton)
            .foregroundStyle(DS.onAccent)
            .background(DS.accent.opacity(configuration.isPressed ? 0.82 : 1), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1).blendMode(.plusLighter))
            .shadow(color: DS.accent.opacity(0.28), radius: 6, y: 2)
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Capsule())
    }
}

public struct QuietButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(DS.body.weight(.medium))
            .padding(.horizontal, DS.md).frame(height: DS.toolButtonSize)
            .background(configuration.isPressed ? DS.hover(scheme) : DS.card(scheme), in: RoundedRectangle(cornerRadius: DS.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.controlRadius).strokeBorder(DS.hairline(scheme)))
            .animation(DS.Motion.hover(reduceMotion), value: configuration.isPressed)
            .opacity(enabled ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: DS.controlRadius))
    }
}

/// Square icon button with a hover wash and an optional selected state.
public struct IconButton: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    @LocalState private var hovering = false
    private let symbol: String
    private let label: String
    private let selected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let selectionSpace: Namespace.ID?
    @FocusState private var focused: Bool
    private let size: CGFloat?
    private let action: () -> Void
    public init(_ symbol: String, label: String, selected: Bool = false, size: CGFloat? = nil, selectionSpace: Namespace.ID? = nil, action: @escaping () -> Void) {
        self.symbol = symbol; self.label = label; self.selected = selected; self.size = size; self.action = action; self.selectionSpace = selectionSpace
    }
    public var body: some View {
        Button(action: action) {
            Icon(symbol, weight: selected ? .fill : .regular, size: DS.iconSize)
                .foregroundStyle(selected ? DS.onAccent : Color.primary.opacity(enabled ? (hovering ? 1 : 0.8) : 0.3))
                .phaseAnimator([1.0, 1.09, 1.0], trigger: selected) { icon, scale in
                    icon.scaleEffect(selected && !reduceMotion ? scale : 1)
                } animation: { _ in DS.Motion.snappy(reduceMotion) }
                .frame(width: size ?? DS.toolButtonSize, height: size ?? DS.toolButtonSize)
                .background {
                    let tile = RoundedRectangle(cornerRadius: DS.buttonRadius, style: .continuous)
                    if selected {
                        tile.fill(DS.accent).slidingSelection("tool", in: selectionSpace, reduceMotion: reduceMotion)
                    } else if hovering && enabled { tile.fill(DS.hover(scheme)) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .animation(DS.Motion.hover(reduceMotion), value: hovering)
        .focused($focused)
        .focusEffectDisabled()
        .overlay(RoundedRectangle(cornerRadius: DS.buttonRadius).strokeBorder(focused ? DS.accent : .clear, lineWidth: DS.insetStroke).allowsHitTesting(false))
        .onHover { hovering = $0 }
        .help(label).accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A row of mutually exclusive choices with a sliding selection.
public struct SegmentedChoice<Value: Hashable>: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var space
    private let options: [(value: Value, title: String, symbol: String?)]
    private let selection: Value
    private let select: (Value) -> Void
    public init(_ options: [(value: Value, title: String, symbol: String?)], selection: Value, select: @escaping (Value) -> Void) {
        self.options = options; self.selection = selection; self.select = select
    }
    public var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                Button { withAnimation(DS.Motion.snappy(reduceMotion)) { select(option.value) } } label: {
                    HStack(spacing: DS.xs) {
                        if let symbol = option.symbol { Icon(symbol, weight: selection == option.value ? .fill : .regular, size: DS.md) }
                        Text(option.title).font(DS.caption)
                    }
                    .foregroundStyle(selection == option.value ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity).frame(height: DS.toolButtonSize - DS.xs)
                    .background {
                        if selection == option.value {
                            RoundedRectangle(cornerRadius: DS.controlRadius, style: .continuous)
                                .fill(scheme == .dark ? Color.white.opacity(0.16) : Color.white)
                                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                                .slidingSelection("selection", in: space, reduceMotion: reduceMotion)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option.value ? .isSelected : [])
            }
        }
        .padding(DS.insetStroke)
        .background(DS.card(scheme), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

// MARK: - Slider

/// A thin slider that shows its value. `onEditingChanged(false)` marks the end of a drag,
/// so callers can preview while dragging and commit once.
public struct ValueSlider: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @LocalState private var dragging = false
    @FocusState private var focused: Bool
    private let title: String
    private let value: Double
    private let range: ClosedRange<Double>
    private let format: (Double) -> String
    public enum Layout { case standard, toolbar, row }
    private let layout: Layout
    private let onChange: (Double) -> Void
    private let onEditingChanged: (Bool) -> Void
    public init(_ title: String, value: Double, in range: ClosedRange<Double>, compact: Bool = false,
                format: @escaping (Double) -> String = { String(format: "%.0f", $0) },
                onChange: @escaping (Double) -> Void, onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.init(title, value: value, in: range, layout: compact ? .toolbar : .standard, format: format, onChange: onChange, onEditingChanged: onEditingChanged)
    }
    public init(_ title: String, value: Double, in range: ClosedRange<Double>, layout: Layout,
                format: @escaping (Double) -> String = { String(format: "%.0f", $0) },
                onChange: @escaping (Double) -> Void, onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.title = title; self.value = value; self.range = range; self.layout = layout
        self.format = format; self.onChange = onChange; self.onEditingChanged = onEditingChanged
    }
    private var fraction: Double { max(0, min(1, (value - range.lowerBound) / (range.upperBound - range.lowerBound))) }
    public var body: some View {
        Group {
            if layout == .row {
                HStack(spacing: DS.sm) {
                    Text(title).font(DS.body).frame(width: DS.sliderLabelWidth, alignment: .leading)
                    track
                    Text(format(value)).font(DS.mono).foregroundStyle(.secondary)
                        .frame(width: DS.sliderReadoutWidth, alignment: .trailing)
                }.frame(height: DS.swatchTileHeight)
            } else if layout == .toolbar {
                VStack(spacing: 0) {
                    HStack(spacing: DS.xs) {
                        Text(title).font(DS.caption).fixedSize()
                        Spacer(minLength: DS.xs)
                        Text(format(value)).font(DS.mono).fixedSize()
                    }
                    .foregroundStyle(.secondary)
                    track
                }
                .frame(width: DS.optionTrackWidth)
            } else {
                VStack(spacing: 6) {
                    HStack {
                        Text(title).font(DS.body)
                        Spacer()
                        Text(format(value)).font(DS.mono).foregroundStyle(dragging ? Color.primary : Color.secondary)
                    }
                    track
                }
            }
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .overlay(RoundedRectangle(cornerRadius: DS.controlRadius)
            .strokeBorder(focused ? DS.accent : .clear).padding(-DS.xs).allowsHitTesting(false))
        .onKeyPress(.leftArrow) { adjust(increasing: false); return .handled }
        .onKeyPress(.rightArrow) { adjust(increasing: true); return .handled }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title).accessibilityValue(format(value))
        .accessibilityAdjustableAction { direction in adjust(increasing: direction == .increment) }
    }
    private func adjust(increasing: Bool) {
        let step = (range.upperBound - range.lowerBound) / 20
        onEditingChanged(true)
        onChange(max(range.lowerBound, min(range.upperBound, value + (increasing ? step : -step))))
        onEditingChanged(false)
    }
    private var track: some View {
        GeometryReader { proxy in
            let knob: CGFloat = 12, width = max(1, proxy.size.width - knob)
            ZStack(alignment: .leading) {
                Capsule().fill(DS.hover(scheme)).frame(height: 4)
                Capsule().fill(DS.accent).frame(width: knob / 2 + width * fraction, height: 4)
                Circle().fill(.white)
                    .shadow(color: .black.opacity(0.3), radius: dragging ? 4 : 2, y: 1)
                    .frame(width: knob, height: knob)
                    .scaleEffect(dragging && !reduceMotion ? 1.15 : 1)
                    .overlay {
                        if dragging {
                            Text(format(value)).font(DS.mono).fixedSize()
                                .padding(.horizontal, DS.sm).padding(.vertical, DS.xs)
                                .foregroundStyle(DS.onAccent).background(DS.accent, in: Capsule())
                                .offset(y: -DS.xl).allowsHitTesting(false)
                                .transition(DS.Motion.pop(reduceMotion: reduceMotion))
                        }
                    }
                    .animation(DS.Motion.snappy(reduceMotion), value: dragging)
                    .offset(x: width * fraction)
            }
            .frame(height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                if !dragging { dragging = true; onEditingChanged(true) }
                let next = max(0, min(1, (gesture.location.x - knob / 2) / width))
                onChange(range.lowerBound + next * (range.upperBound - range.lowerBound))
            }.onEnded { _ in dragging = false; onEditingChanged(false) })
        }
        .frame(height: layout == .toolbar ? 12 : 16)
    }
}

// MARK: - Small pieces

/// Keyboard shortcut rendered as individual keycaps.
public struct Keycaps: View {
    @Environment(\.colorScheme) private var scheme
    private let keys: [String]
    public init(_ shortcut: String) { keys = shortcut.map { String($0) } }
    public var body: some View {
        HStack(spacing: DS.xs) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key).font(DS.mono)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(DS.hover(scheme), in: RoundedRectangle(cornerRadius: DS.xs, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: DS.xs, style: .continuous).strokeBorder(DS.hairline(scheme)))
            }
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(keys.joined())
    }
}

/// The SuperShot logo. Kept for existing call sites; draws `BrandIcon`, the same art as the app icon.
public struct BrandMark: View {
    private let size: CGFloat
    public init(size: CGFloat = 44) { self.size = size }
    public var body: some View { BrandIcon(size: size).accessibilityHidden(true) }
}

/// Small rounded tag for metadata such as dimensions.
public struct Tag: View {
    @Environment(\.colorScheme) private var scheme
    private let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text).font(DS.mono).foregroundStyle(.secondary)
            .padding(.horizontal, DS.sm).frame(height: DS.metadataIconSize)
            .background(DS.card(scheme), in: RoundedRectangle(cornerRadius: DS.controlRadius))
    }
}

/// An accent-colored switch that looks the same in key, inactive, and offscreen windows.
public struct SwitchStyle: ToggleStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    private let showsLabel: Bool
    public init(showsLabel: Bool = false) { self.showsLabel = showsLabel }
    public func makeBody(configuration: Configuration) -> some View {
        Button { withAnimation(DS.Motion.snappy(reduceMotion)) { configuration.isOn.toggle() } } label: {
            HStack(spacing: DS.sm) {
                if showsLabel { configuration.label.font(DS.caption).fixedSize() }
                Capsule().fill(configuration.isOn ? DS.accent : DS.hover(scheme))
                    .overlay(Capsule().strokeBorder(DS.hairline(scheme)))
                    .frame(width: 34, height: 20)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(configuration.isOn ? DS.onAccent : DS.white).shadow(color: .black.opacity(0.25), radius: 1.5, y: 1).frame(width: 16, height: 16).padding(2)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).opacity(enabled ? 1 : 0.45)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}
