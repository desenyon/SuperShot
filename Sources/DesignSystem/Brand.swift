import SwiftUI
import AppKit

/// The one SuperShot logo: a bold white viewfinder of four rounded corner arcs on a Clear-blue tile.
/// Every place the brand appears draws it from here, so the app icon, the in-app mark,
/// and the menu bar item cannot drift apart.
public enum Brand {
    /// Tile gradient (top-left light to bottom-right deep) and glyph color. Blue only; no purple.
    public static let tileLight: UInt32 = 0x5AA2FF, tileMid: UInt32 = 0x2F7CF6, tileDeep: UInt32 = 0x1456D9
    public static let glyph: UInt32 = 0xFFFFFF

    /// The viewfinder: a rounded square whose sides are cut away in the middle, leaving four corner arcs.
    static func glyphPath(in rect: CGRect) -> CGPath {
        let side = rect.width * 0.45
        let square = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
        let radius = side * 0.27, arm = side * 0.05
        let path = CGMutablePath()
        // Each corner: arm along one edge, quarter arc, arm along the other edge.
        let corners: [(CGPoint, CGFloat, CGFloat)] = [(CGPoint(x: square.minX, y: square.minY), 1, 1), (CGPoint(x: square.maxX, y: square.minY), -1, 1),
                                                      (CGPoint(x: square.maxX, y: square.maxY), -1, -1), (CGPoint(x: square.minX, y: square.maxY), 1, -1)]
        for (corner, sx, sy) in corners {
            path.move(to: CGPoint(x: corner.x, y: corner.y + sy * (radius + arm)))
            path.addLine(to: CGPoint(x: corner.x, y: corner.y + sy * radius))
            path.addArc(tangent1End: corner, tangent2End: CGPoint(x: corner.x + sx * radius, y: corner.y), radius: radius)
            path.addLine(to: CGPoint(x: corner.x + sx * (radius + arm), y: corner.y))
        }
        return path
    }
    static func glyphLineWidth(in rect: CGRect) -> CGFloat { rect.width * 0.45 * 0.10 }

    /// Draws the glyph into `rect` (the full icon square) in the current CG context.
    /// `monochrome` draws it in that color for template use (menu bar); `weight` scales the stroke.
    public static func drawGlyph(in rect: CGRect, context: CGContext, monochrome color: CGColor? = nil, weight: CGFloat = 1) {
        context.saveGState()
        context.setLineWidth(glyphLineWidth(in: rect) * weight); context.setLineCap(.round); context.setLineJoin(.round)
        if color == nil {
            context.setShadow(offset: CGSize(width: 0, height: -rect.width * 0.008), blur: rect.width * 0.03, color: cg(0x0A2A6B, alpha: 0.35))
        }
        context.setStrokeColor(color ?? cg(glyph))
        context.addPath(glyphPath(in: rect)); context.strokePath()
        context.restoreGState()
    }

    /// The full app icon: rounded blue tile with a diagonal gradient, soft top light, hairline edge, and glyph.
    /// Matches macOS icon geometry: an 824 pt tile centred in a 1024 pt canvas.
    public static func drawIcon(in rect: CGRect, context: CGContext) {
        let unit = rect.width / 1024
        let tile = rect.insetBy(dx: 100 * unit, dy: 100 * unit)
        let radius = 186 * unit
        let shape = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let space = CGColorSpace(name: CGColorSpace.sRGB)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -10 * unit), blur: 24 * unit, color: CGColor(gray: 0, alpha: 0.3))
        context.addPath(shape); context.setFillColor(cg(tileMid)); context.fillPath()
        context.restoreGState()
        context.saveGState()
        context.addPath(shape); context.clip()
        let body = CGGradient(colorsSpace: space, colors: [cg(tileLight), cg(tileMid), cg(tileDeep)] as CFArray, locations: [0, 0.48, 1])!
        context.drawLinearGradient(body, start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY), options: [])
        let light = CGGradient(colorsSpace: space, colors: [CGColor(gray: 1, alpha: 0.22), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1])!
        context.drawRadialGradient(light, startCenter: CGPoint(x: tile.midX - tile.width * 0.18, y: tile.maxY + tile.height * 0.05), startRadius: 0,
                                   endCenter: CGPoint(x: tile.midX - tile.width * 0.18, y: tile.maxY + tile.height * 0.05), endRadius: tile.height * 0.85, options: [])
        let floor = CGGradient(colorsSpace: space, colors: [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0.16)] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(floor, start: CGPoint(x: tile.midX, y: tile.midY), end: CGPoint(x: tile.midX, y: tile.minY), options: [])
        context.restoreGState()
        context.saveGState()
        context.addPath(CGPath(roundedRect: tile.insetBy(dx: unit * 2, dy: unit * 2), cornerWidth: radius - unit * 2, cornerHeight: radius - unit * 2, transform: nil))
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.22)); context.setLineWidth(4 * unit); context.strokePath()
        context.restoreGState()
        drawGlyph(in: rect, context: context)
    }

    /// The app icon as an image, for the bundle's .icns and in-app marks.
    public static func iconImage(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            drawIcon(in: rect, context: context); return true
        }
    }

    /// The glyph alone as a template image, for the menu bar.
    public static func menuBarImage(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            // Enlarge the glyph to fill the menu bar square, and keep the stroke legible at 18 pt.
            drawGlyph(in: rect.insetBy(dx: -rect.width * 0.55, dy: -rect.height * 0.55), context: context,
                      monochrome: CGColor(gray: 0, alpha: 1), weight: 0.85)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "SuperShot"
        return image
    }

    /// Writes a 1024 px PNG of the app icon. Used by scripts/bundle.sh through `--render-app-icon`.
    public static func writeIconPNG(to url: URL) throws {
        let size = 1024
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                                            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw CocoaError(.fileWriteUnknown) }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        drawIcon(in: CGRect(x: 0, y: 0, width: size, height: size), context: context.cgContext)
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url)
    }

    static func cg(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

/// The app icon as a SwiftUI view: the same drawing as the Dock and Finder icon.
public struct BrandIcon: View {
    private let size: CGFloat
    public init(size: CGFloat = 44) { self.size = size }
    public var body: some View {
        // The icon art includes macOS's transparent margin; scale it so the tile fills `size`.
        Image(nsImage: Brand.iconImage(size: size * 1024 / 824))
            .resizable().interpolation(.high)
            .frame(width: size * 1024 / 824, height: size * 1024 / 824)
            .frame(width: size, height: size)
            .accessibilityLabel("SuperShot")
    }
}
