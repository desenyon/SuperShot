import SwiftUI

public extension DS {
    @MainActor static var toolButtonSize: CGFloat { ThemeState.shared.density == .compact ? 28 : 32 }
    @MainActor static var capsulePadding: CGFloat { ThemeState.shared.density == .compact ? 4 : 5 }
    @MainActor static var panelPadding: CGFloat { ThemeState.shared.density == .compact ? md : lg }
    @MainActor static var capsuleHeight: CGFloat { toolButtonSize + capsulePadding * 2 }
    static let buttonRadius: CGFloat = 9
    static let insetStroke: CGFloat = 2
    static let optionTrackWidth: CGFloat = 88
    static let windowControlsClearance: CGFloat = 80
    static let sliderLabelWidth: CGFloat = 56
    static let sliderReadoutWidth: CGFloat = 32
    static let swatchDiameter: CGFloat = 16
    static let swatchTileHeight: CGFloat = 28
    static let alignmentTarget: CGFloat = 20
    static let zoomLabelWidth: CGFloat = 52
    static let canvasGlowRadius: CGFloat = 760
    static func canvasGlow(_ scheme: ColorScheme) -> Color { white.opacity(scheme == .dark ? 0.045 : 0.58) }
    static let pinPopoverWidth: CGFloat = 168
    static let historyCardWidth: CGFloat = 256
    static let historySearchWidth: CGFloat = 288
    static let historyFilterWidth: CGFloat = 196
    static let windowHeaderInset: CGFloat = 44
    static let metadataIconSize: CGFloat = 20
}

public extension View {
    /// Retain the same selection identity across a group, with an opacity-only alternative.
    @ViewBuilder func slidingSelection(_ id: String, in namespace: Namespace.ID?, reduceMotion: Bool) -> some View {
        if let namespace, !reduceMotion {
            matchedGeometryEffect(id: id, in: namespace)
        } else { transition(.opacity) }
    }
}

public extension DS.Motion {
    /// Layer counterpart to gentle for discrete backdrop changes.
    static func canvasFade(reduceMotion: Bool) -> CATransition {
        let fade = CATransition()
        fade.type = .fade
        fade.duration = reduceMotion ? 0.14 : 0.25
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return fade
    }
}
