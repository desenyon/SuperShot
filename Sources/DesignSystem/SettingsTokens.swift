import SwiftUI
import AppKit

public extension DS {
    /// Settings uses graphite rather than the editor's annotation accent.
    /// Keeping this palette separate prevents preference styling from changing other windows.
    enum Preferences {
        public static let sidebar: CGFloat = 172
        public static let contentWidth: CGFloat = 640
        public static let pageInset: CGFloat = 24
        public static let titlebarInset: CGFloat = 40
        public static let sectionGap: CGFloat = 20
        public static let groupInset: CGFloat = 12
        public static let rowHeight: CGFloat = 30
        public static let navigationHeight: CGFloat = 30
        public static let controlHeight: CGFloat = 26
        public static let controlWidth: CGFloat = 184
        public static let radius: CGFloat = 8
        public static let controlRadius: CGFloat = 5
        public static let hairline: CGFloat = 0.5
        public static let focusWidth: CGFloat = 1.5
        public static let switchSize = CGSize(width: 30, height: 18)
        public static let switchThumb: CGFloat = 14
        public static let title = Font.system(size: 17, weight: .semibold)
        public static let label = Font.system(size: 13)
        public static let detail = Font.system(size: 11)
        public static let section = Font.system(size: 11, weight: .medium)
        public static let mono = Font.system(size: 11, design: .monospaced).monospacedDigit()
        public static func canvas(_ scheme: ColorScheme) -> Color { DS.color(scheme == .dark ? 0x242424 : 0xF5F5F5) }
        public static func sidebarFallback(_ scheme: ColorScheme) -> Color { DS.color(scheme == .dark ? 0x292929 : 0xECECEC) }
        public static func groupFallback(_ scheme: ColorScheme) -> Color { DS.color(scheme == .dark ? 0x2B2B2B : 0xFCFCFC) }
        public static func accent(_ scheme: ColorScheme) -> Color { DS.color(scheme == .dark ? 0xC4C4C4 : 0x595959) }
        public static func switchTrack(on: Bool, scheme: ColorScheme) -> Color {
            DS.color(scheme == .dark ? (on ? 0x878787 : 0x505050) : (on ? 0x626262 : 0xADADAD))
        }
        public static func fill(_ scheme: ColorScheme) -> Color { Color.primary.opacity(scheme == .dark ? 0.065 : 0.035) }
        public static func selection(_ scheme: ColorScheme) -> Color { Color.primary.opacity(scheme == .dark ? 0.12 : 0.075) }
        public static func edge(_ scheme: ColorScheme) -> Color { Color.primary.opacity(scheme == .dark ? 0.13 : 0.12) }
        public static func raised(_ scheme: ColorScheme) -> Color { DS.color(scheme == .dark ? 0x515151 : 0xFFFFFF) }
        public static var nsFocus: NSColor { .labelColor.withAlphaComponent(0.65) }
    }
}
