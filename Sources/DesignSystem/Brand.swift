import SwiftUI
import AppKit

/// The one SuperShot logo: four rounded viewfinder corners around a focus dot.
/// Every place the brand appears draws it from here, so the app icon, the in-app mark,
/// and the menu bar item cannot drift apart.
public enum Brand {
    /// Tile and glyph colors. Graphite and a cool light blue; no purple.
    public static let tileTop: UInt32 = 0x23262D, tileBottom: UInt32 = 0x0B0C0F
    public static let glyphTop: UInt32 = 0xC9DCFF, glyphBottom: UInt32 = 0x8DB6FF
    public static let focus: UInt32 = 0x2F7CF6

    /// Draws the glyph into `rect` (the full icon square) in the current CG context.
    /// `monochrome` draws everything in `color` for template use (menu bar).
    public static func drawGlyph(in rect: CGRect, context: CGContext, monochrome color: CGColor? = nil, weight: CGFloat = 1) {
        let unit = rect.width / 1024
        let inset = rect.insetBy(dx: 300 * unit, dy: 300 * unit)
        let arm = 124 * unit, bend = 40 * unit
        let path = CGMutablePath()
        for (corner, sx, sy) in [(CGPoint(x: inset.minX, y: inset.minY), 1.0, 1.0), (CGPoint(x: inset.maxX, y: inset.minY), -1.0, 1.0),
                                 (CGPoint(x: inset.minX, y: inset.maxY), 1.0, -1.0), (CGPoint(x: inset.maxX, y: inset.maxY), -1.0, -1.0)] {
            path.move(to: CGPoint(x: corner.x, y: corner.y + sy * arm))
            path.addLine(to: CGPoint(x: corner.x, y: corner.y + sy * bend))
            path.addQuadCurve(to: CGPoint(x: corner.x + sx * bend, y: corner.y), control: corner)
            path.addLine(to: CGPoint(x: corner.x + sx * arm, y: corner.y))
        }
        context.saveGState()
        context.setLineWidth(46 * unit * weight); context.setLineCap(.round); context.setLineJoin(.round)
        let dot = CGRect(x: rect.midX - 34 * unit, y: rect.midY - 34 * unit, width: 68 * unit, height: 68 * unit)
        if let color {
            context.setStrokeColor(color); context.addPath(path); context.strokePath()
            context.setFillColor(color); context.fillEllipse(in: dot)
        } else {
            context.addPath(path); context.replacePathWithStrokedPath(); context.clip()
            let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [cg(glyphTop), cg(glyphBottom)] as CFArray, locations: [0, 1])!
            context.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: inset.maxY), end: CGPoint(x: rect.midX, y: inset.minY), options: [])
            context.resetClip()
            context.setShadow(offset: .zero, blur: 40 * unit, color: cg(focus, alpha: 0.7))
            context.setFillColor(cg(focus)); context.fillEllipse(in: dot)
        }
        context.restoreGState()
    }

    /// The full app icon: rounded graphite tile with a soft top light, hairline edge, and glyph.
    /// Matches macOS icon geometry: an 824 pt tile centred in a 1024 pt canvas.
    public static func drawIcon(in rect: CGRect, context: CGContext) {
        let unit = rect.width / 1024
        let tile = rect.insetBy(dx: 100 * unit, dy: 100 * unit)
        let radius = 186 * unit
        let shape = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -12 * unit), blur: 28 * unit, color: CGColor(gray: 0, alpha: 0.35))
        context.addPath(shape); context.setFillColor(cg(tileBottom)); context.fillPath()
        context.restoreGState()
        context.saveGState()
        context.addPath(shape); context.clip()
        let space = CGColorSpace(name: CGColorSpace.sRGB)
        let body = CGGradient(colorsSpace: space, colors: [cg(tileTop), cg(tileBottom)] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(body, start: CGPoint(x: tile.midX, y: tile.maxY), end: CGPoint(x: tile.midX, y: tile.minY), options: [])
        let light = CGGradient(colorsSpace: space, colors: [CGColor(gray: 1, alpha: 0.10), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1])!
        context.drawRadialGradient(light, startCenter: CGPoint(x: tile.midX, y: tile.maxY), startRadius: 0,
                                   endCenter: CGPoint(x: tile.midX, y: tile.maxY), endRadius: tile.height * 0.9, options: [])
        context.restoreGState()
        context.saveGState()
        context.addPath(CGPath(roundedRect: tile.insetBy(dx: unit * 1.5, dy: unit * 1.5), cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.12)); context.setLineWidth(3 * unit); context.strokePath()
        context.restoreGState()
        drawGlyph(in: tile.insetBy(dx: -100 * unit, dy: -100 * unit), context: context)
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
            // Enlarge the glyph to fill the menu bar square, and thicken it for legibility at 18 pt.
            drawGlyph(in: rect.insetBy(dx: -rect.width * 0.36, dy: -rect.height * 0.36), context: context,
                      monochrome: CGColor(gray: 0, alpha: 1), weight: 1.25)
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
