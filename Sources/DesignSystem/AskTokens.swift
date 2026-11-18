import AppKit
import SwiftUI

public extension DS {
    enum Ask {
        public static let panelSize = CGSize(width: 380, height: 600)
        public static let editorWidth: CGFloat = 360
        public static let thumbnail = CGSize(width: 56, height: 36)
        public static let cell: CGFloat = 44
        /// Labeled cells need room for "Capture" at the HUD label size.
        public static let labeledCellWidth: CGFloat = 56
        public static let send: CGFloat = 28
        public static let bubble: CGFloat = 14
        public static let hud = NSColor(white: 0.09, alpha: 0.96)
        public static let hudEdge = NSColor.white.withAlphaComponent(0.18)
        public static let hudShadow = NSColor.black.withAlphaComponent(0.45)
        public static let hudWash = NSColor.white.withAlphaComponent(0.12)
        @MainActor public static let hudLabel = NSFont.systemFont(ofSize: 10.5, weight: .medium)
    }
}
