import SwiftUI
import AppKit

public extension DS {
    /// Settings uses a tinted navigation surface and neutral groups in the detail pane.
    enum Preferences {
        public static let sidebar: CGFloat = 208
        public static let compactSidebar: CGFloat = 194
        public static let iconSidebar: CGFloat = 52
        public static let compactWindowWidth: CGFloat = 740
        public static let shortWindowHeight: CGFloat = 560
        public static let navigationRadius: CGFloat = 16
        public static let navigationRowRadius: CGFloat = 8
        public static let railTitlebarHeight: CGFloat = 40
        public static let railInset: CGFloat = 8
        public static let contentWidth: CGFloat = 640
        public static let pageInset: CGFloat = 28
        public static let titlebarInset: CGFloat = 40
        public static let sectionGap: CGFloat = 24
        public static let groupInset: CGFloat = 4
        public static let rowHeight: CGFloat = 44
        public static let compactHeight: CGFloat = 30
        public static let tile: CGFloat = 22
        public static let navigationHeight: CGFloat = 32
        public static let navigationTileHeight: CGFloat = 40
        public static let controlHeight: CGFloat = 26
        public static let controlWidth: CGFloat = 184
        public static let rowLabelWidth: CGFloat = 148
        public static let shortcutColumnWidth: CGFloat = 194
        public static let shortcutRecorderWidth: CGFloat = 124
        public static let shortcutRemoveWidth: CGFloat = 18
        public static let previewHeight: CGFloat = 72
        public static let previewThumbnailScale: CGFloat = 6
        public static let previewPinHeight: CGFloat = 104
        public static let previewPinScale: CGFloat = 8
        public static let previewAspectRatio: CGFloat = 1.6
        public static let sliderValueWidth: CGFloat = 46
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
        public static let sidebarLabel = Font.system(size: 14)
        public static let sidebarHeading = Font.system(size: 12, weight: .medium)
        public static let pageTitle = Font.system(size: 27, weight: .medium)
        public static let label = Font.system(size: 13)
        public static let detail = Font.system(size: 11)
        public static let section = Font.system(size: 11, weight: .medium)
        public static let mono = Font.system(size: 11, design: .monospaced).monospacedDigit()
        public static func canvas(_ scheme: ColorScheme) -> Color { DS.color(scheme == .dark ? 0x151519 : 0xF7F7F9) }
        public static func sidebarFallback(_ scheme: ColorScheme) -> Color { DS.color(scheme == .dark ? 0x3028BA : 0x352FC1) }
        public static func sidebarTint(_ scheme: ColorScheme) -> Color { DS.color(scheme == .dark ? 0x3329CB : 0x3B33D2) }
        public static let sidebarInk = Color.white
        public static let sidebarSecondary = DS.color(0xD5D4FC)
        public static let sidebarDivider = Color.white.opacity(0.13)
        public static let sidebarTile = Color.white.opacity(0.075)
        public static let sidebarSelection = Color.white.opacity(0.19)
        public static let sidebarFocus = Color.white.opacity(0.85)
        public static let sidebarReflection = Color.white.opacity(0.09)
        public static func groupFallback(_ scheme: ColorScheme) -> Color { DS.color(scheme == .dark ? 0x222C39 : 0xFFFFFF) }
        @MainActor public static func accent(_ scheme: ColorScheme) -> Color { DS.actionInk(scheme) }
        public static func switchTrack(on: Bool, scheme: ColorScheme) -> Color {
            DS.color(scheme == .dark ? (on ? 0x878787 : 0x505050) : (on ? 0x626262 : 0xADADAD))
        }
        public static func fill(_ scheme: ColorScheme) -> Color { Color.primary.opacity(scheme == .dark ? 0.075 : 0.05) }
        public static func selection(_ scheme: ColorScheme) -> Color { Color.primary.opacity(scheme == .dark ? 0.16 : 0.13) }
        public static func edge(_ scheme: ColorScheme) -> Color { Color.primary.opacity(scheme == .dark ? 0.15 : 0.14) }
        public static func controlEdge(_ scheme: ColorScheme) -> Color { Color.primary.opacity(scheme == .dark ? 0.27 : 0.25) }
        public static func raised(_ scheme: ColorScheme) -> Color { DS.color(scheme == .dark ? 0x515151 : 0xDDDDDD) }
        public static func tileFill(_ scheme: ColorScheme, selected: Bool) -> LinearGradient {
            let values: (UInt32, UInt32) = switch (scheme, selected) {
            case (.dark, true): (0x636363, 0x404040)
            case (.dark, false): (0x444444, 0x333333)
            case (_, true): (0xFFFFFF, 0xDDDDDD)
            case (_, false): (0xFAFAFA, 0xE8E8E8)
            }
            return LinearGradient(colors: [DS.color(values.0), DS.color(values.1)], startPoint: .top, endPoint: .bottom)
        }
        @MainActor public static var nsFocus: NSColor { DS.accentPalette(ThemeState.shared.accent).bright }
    }
}
