import SwiftUI
import AppKit

public extension DS {
    /// Settings uses graphite rather than the editor's annotation accent.
    /// Keeping this palette separate prevents preference styling from changing other windows.
    enum Preferences {
        public static let sidebar: CGFloat = 180
        public static let shortWindowHeight: CGFloat = 560
        public static let contentWidth: CGFloat = 640
        public static let pageInset: CGFloat = 24
        public static let titlebarInset: CGFloat = 40
        public static let sectionGap: CGFloat = 20
        public static let groupInset: CGFloat = 12
        public static let rowHeight: CGFloat = 44
        public static let compactHeight: CGFloat = 30
        public static let tile: CGFloat = 22
        public static let navigationHeight: CGFloat = 28
        public static let controlHeight: CGFloat = 26
        public static let controlWidth: CGFloat = 184
        public static let radius: CGFloat = 12
        public static let controlRadius: CGFloat = 6
        public static let hairline: CGFloat = 0.5
        public static let focusWidth: CGFloat = 1.5
        public static let switchSize = CGSize(width: 30, height: 18)
        public static let switchThumb: CGFloat = 14
        public static let helpWidth: CGFloat = 440
        public static let swatch: CGFloat = 28
        public static let meterWidth: CGFloat = 104
        public static let navigation = Font.system(size: 13, weight: .medium)
        public static let title = Font.system(size: 22, weight: .semibold)
        public static let label = Font.system(size: 13)
        public static let detail = Font.system(size: 11)
        public static let section = Font.system(size: 11, weight: .medium)
        public static let mono = Font.system(size: 11, design: .monospaced).monospacedDigit()
        public static func canvas(_ scheme: ColorScheme) -> Color { DS.color(scheme == .dark ? 0x202020 : 0xF7F7F7) }
        public static func sidebarFallback(_ scheme: ColorScheme) -> Color { DS.color(scheme == .dark ? 0x252525 : 0xEFEFEF) }
        public static func groupFallback(_ scheme: ColorScheme) -> Color { DS.color(scheme == .dark ? 0x2A2A2A : 0xFFFFFF) }
        public static func accent(_ scheme: ColorScheme) -> Color { DS.color(scheme == .dark ? 0xC4C4C4 : 0x595959) }
        public static func switchTrack(on: Bool, scheme: ColorScheme) -> Color {
            DS.color(scheme == .dark ? (on ? 0x878787 : 0x505050) : (on ? 0x626262 : 0xADADAD))
        }
        public static func fill(_ scheme: ColorScheme) -> Color { Color.primary.opacity(scheme == .dark ? 0.065 : 0.035) }
        public static func selection(_ scheme: ColorScheme) -> Color { Color.primary.opacity(scheme == .dark ? 0.12 : 0.075) }
        public static func edge(_ scheme: ColorScheme) -> Color { Color.primary.opacity(scheme == .dark ? 0.13 : 0.12) }
        public static func raised(_ scheme: ColorScheme) -> Color { DS.color(scheme == .dark ? 0x515151 : 0xFFFFFF) }
        public static func tileFill(_ scheme: ColorScheme, selected: Bool) -> LinearGradient {
            let values: (UInt32, UInt32) = switch (scheme, selected) {
            case (.dark, true): (0x636363, 0x404040)
            case (.dark, false): (0x444444, 0x333333)
            case (_, true): (0xFFFFFF, 0xDDDDDD)
            case (_, false): (0xFAFAFA, 0xE8E8E8)
            }
            return LinearGradient(colors: [DS.color(values.0), DS.color(values.1)], startPoint: .top, endPoint: .bottom)
        }
        public static func cardShadow(_ scheme: ColorScheme) -> Color { .black.opacity(scheme == .light ? 0.055 : 0) }
        public static var nsFocus: NSColor { .labelColor.withAlphaComponent(0.65) }
    }
}
