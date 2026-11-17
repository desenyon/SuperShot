import SwiftUI
import AppKit

/// Shared tokens. Feature code takes colors, type, spacing, radii, and motion from here.
public enum DS {
    // MARK: Color

    /// The single accent. Used for selection and primary actions only.
    public static let accent = Color(red: 0.36, green: 0.42, blue: 1.0)
    public static let accentBright = Color(red: 0.55, green: 0.61, blue: 1.0)
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
    public static func actionInk(_ scheme: ColorScheme) -> Color { scheme == .dark ? accentBright : accent }
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
    public static var nsAccent: NSColor { NSColor(srgbRed: 0.36, green: 0.42, blue: 1.0, alpha: 1) }
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
        NSColor(srgbRed: 0.64, green: 0.40, blue: 1.00, alpha: 1),
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
        GradientPreset(id: "iris", name: "Iris", hex: [0x6A5BFF, 0xB06CFF, 0xFF8FB8], angle: 45),
        GradientPreset(id: "sunset", name: "Sunset", hex: [0xFF5F6D, 0xFF9966, 0xFFC371], angle: 45),
        GradientPreset(id: "ocean", name: "Ocean", hex: [0x1E3CFF, 0x2D9CFF, 0x5CE1E6], angle: 45),
        GradientPreset(id: "mint", name: "Mint", hex: [0x0BA360, 0x3CBA92, 0xB5F0D0], angle: 45),
        GradientPreset(id: "candy", name: "Candy", hex: [0xFF9A9E, 0xFAD0C4, 0xFBC2EB], angle: 45),
        GradientPreset(id: "sky", name: "Sky", hex: [0x4D8DFF, 0x9CC9FF, 0xE8F4FF], angle: 90),
        GradientPreset(id: "ember", name: "Ember", hex: [0x2B0A3D, 0xB3123F, 0xFF7A3D], angle: 45),
        GradientPreset(id: "aurora", name: "Aurora", hex: [0x0F2027, 0x1F6F78, 0x7FFFD4], angle: 60),
        GradientPreset(id: "grape", name: "Grape", hex: [0x41106B, 0x7F3FBF, 0xC59BFF], angle: 45),
        GradientPreset(id: "sand", name: "Sand", hex: [0xF6EFE3, 0xE6D5BD, 0xCDB592], angle: 45),
        GradientPreset(id: "graphite", name: "Graphite", hex: [0x2A2C31, 0x16171A], angle: 90),
        GradientPreset(id: "cloud", name: "Cloud", hex: [0xFFFFFF, 0xE9ECF2], angle: 90)
    ]

    static let solidHex: [UInt32] = [
        0xFFFFFF, 0xF1F2F4, 0x1C1D21, 0x000000, 0xFF5A5F, 0xFF9F1C,
        0xFFD23F, 0x3DDC97, 0x2EC4B6, 0x3A86FF, 0x7B5CFF, 0xFF6FB5
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
    public init(radius: CGFloat = DS.radius) { self.radius = radius }
    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if DS.rendersOffscreen || reduceTransparency {
            content
                .background(DS.panel(scheme), in: shape)
                .overlay(shape.strokeBorder(DS.hairline(scheme), lineWidth: DS.stroke))
                .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.14), radius: 18, y: 8)
        } else {
            content.glassEffect(.regular, in: shape)
        }
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
            .foregroundStyle(.white)
            .background(DS.accent.opacity(configuration.isPressed ? 0.78 : 1), in: Capsule())
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Capsule())
    }
}

public struct QuietButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(DS.body.weight(.medium))
            .padding(.horizontal, DS.md).frame(height: DS.toolButton)
            .background(configuration.isPressed ? DS.hover(scheme).opacity(1.6) : DS.hover(scheme), in: RoundedRectangle(cornerRadius: DS.controlRadius, style: .continuous))
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
    private let size: CGFloat
    private let action: () -> Void
    public init(_ symbol: String, label: String, selected: Bool = false, size: CGFloat = DS.toolButton, action: @escaping () -> Void) {
        self.symbol = symbol; self.label = label; self.selected = selected; self.size = size; self.action = action
    }
    public var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: DS.icon, weight: .medium))
                .foregroundStyle(selected ? Color.white : Color.primary.opacity(enabled ? 0.86 : 0.3))
                .frame(width: size, height: size)
                .background(selected ? DS.accent : (hovering && enabled ? DS.hover(scheme) : .clear),
                            in: RoundedRectangle(cornerRadius: DS.controlRadius, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                Button { withAnimation(DS.spring(reduceMotion: reduceMotion)) { select(option.value) } } label: {
                    HStack(spacing: DS.xs) {
                        if let symbol = option.symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)) }
                        Text(option.title).font(DS.caption)
                    }
                    .foregroundStyle(selection == option.value ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity).frame(height: 26)
                    .background {
                        if selection == option.value {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(scheme == .dark ? Color.white.opacity(0.16) : Color.white)
                                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                                .matchedGeometryEffect(id: "selection", in: space)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option.value ? .isSelected : [])
            }
        }
        .padding(2)
        .background(DS.card(scheme), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

// MARK: - Slider

/// A thin slider that shows its value. `onEditingChanged(false)` marks the end of a drag,
/// so callers can preview while dragging and commit once.
public struct ValueSlider: View {
    @Environment(\.colorScheme) private var scheme
    @LocalState private var dragging = false
    private let title: String
    private let value: Double
    private let range: ClosedRange<Double>
    private let format: (Double) -> String
    private let compact: Bool
    private let onChange: (Double) -> Void
    private let onEditingChanged: (Bool) -> Void
    public init(_ title: String, value: Double, in range: ClosedRange<Double>, compact: Bool = false,
                format: @escaping (Double) -> String = { String(format: "%.0f", $0) },
                onChange: @escaping (Double) -> Void, onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.title = title; self.value = value; self.range = range; self.compact = compact
        self.format = format; self.onChange = onChange; self.onEditingChanged = onEditingChanged
    }
    private var fraction: Double { max(0, min(1, (value - range.lowerBound) / (range.upperBound - range.lowerBound))) }
    public var body: some View {
        Group {
            if compact {
                HStack(spacing: DS.sm) {
                    Text(title).font(DS.caption).foregroundStyle(.secondary).fixedSize()
                    track.frame(width: 76)
                    Text(format(value)).font(DS.mono).foregroundStyle(.secondary).frame(width: 30, alignment: .trailing)
                }
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title).accessibilityValue(format(value))
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 20
            onChange(max(range.lowerBound, min(range.upperBound, value + (direction == .increment ? step : -step))))
            onEditingChanged(false)
        }
    }
    private var track: some View {
        GeometryReader { proxy in
            let knob: CGFloat = 14, width = max(1, proxy.size.width - knob)
            ZStack(alignment: .leading) {
                Capsule().fill(DS.hover(scheme)).frame(height: 4)
                Capsule().fill(DS.accent).frame(width: knob / 2 + width * fraction, height: 4)
                Circle().fill(.white)
                    .shadow(color: .black.opacity(0.3), radius: dragging ? 4 : 2, y: 1)
                    .frame(width: knob, height: knob)
                    .scaleEffect(dragging ? 1.12 : 1)
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
        .frame(height: 18)
    }
}

// MARK: - Small pieces

/// Keyboard shortcut rendered as individual keycaps.
public struct Keycaps: View {
    @Environment(\.colorScheme) private var scheme
    private let keys: [String]
    public init(_ shortcut: String) { keys = shortcut.map { String($0) } }
    public var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key).font(.system(size: 11, weight: .medium, design: .rounded))
                    .frame(minWidth: 20, minHeight: 20)
                    .background(DS.hover(scheme), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(DS.hairline(scheme)))
            }
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(keys.joined())
    }
}

/// The app glyph: a viewfinder inside an accent tile.
public struct BrandMark: View {
    private let size: CGFloat
    public init(size: CGFloat = 44) { self.size = size }
    public var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(LinearGradient(colors: [DS.color(0x7C6BFF), DS.color(0x3D55F5)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(Image(systemName: "viewfinder").font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white))
            .shadow(color: DS.accent.opacity(0.4), radius: size * 0.22, y: size * 0.1)
            .accessibilityHidden(true)
    }
}

/// Small rounded tag for metadata such as dimensions.
public struct Tag: View {
    @Environment(\.colorScheme) private var scheme
    private let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text).font(DS.mono).foregroundStyle(.secondary)
            .padding(.horizontal, 7).frame(height: 20)
            .background(DS.hover(scheme), in: Capsule())
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
        Button { withAnimation(DS.quick(reduceMotion: reduceMotion)) { configuration.isOn.toggle() } } label: {
            HStack(spacing: DS.sm) {
                if showsLabel { configuration.label.font(DS.caption).fixedSize() }
                Capsule().fill(configuration.isOn ? DS.accent : (scheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.16)))
                    .frame(width: 34, height: 20)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(.white).shadow(color: .black.opacity(0.25), radius: 1.5, y: 1).frame(width: 16, height: 16).padding(2)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).opacity(enabled ? 1 : 0.45)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}
