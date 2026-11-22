import CoreImage
import CoreText
import Foundation

public struct RecordingAnnotation: Identifiable, Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case arrow, outline, text, spotlight, cover, highlight, blur
    }

    public enum Ink: String, Codable, CaseIterable, Sendable {
        case blue, white, red, yellow

        public var color: CGColor {
            switch self {
            case .blue: CGColor(red: 0.18, green: 0.51, blue: 1, alpha: 1)
            case .white: CGColor(gray: 1, alpha: 1)
            case .red: CGColor(red: 1, green: 0.34, blue: 0.28, alpha: 1)
            case .yellow: CGColor(red: 1, green: 0.79, blue: 0.19, alpha: 1)
            }
        }
    }

    public var id: UUID
    public var kind: Kind
    public var range: RecordingRange
    /// Positions use normalized top-left coordinates in the final video frame.
    public var start: CGPoint
    public var end: CGPoint
    public var ink: Ink
    public var text: String

    public init(id: UUID = UUID(), kind: Kind, range: RecordingRange, start: CGPoint, end: CGPoint,
                ink: Ink = .blue, text: String = "") {
        self.id = id
        self.kind = kind
        self.range = range
        self.start = start
        self.end = end
        self.ink = ink
        self.text = text
    }
}

enum RecordingAnnotationRenderer {
    static func render(_ annotations: [RecordingAnnotation], at time: TimeInterval, over frame: CIImage) -> CIImage {
        let bounds = frame.extent
        var image = frame
        for item in annotations where item.range.start <= time && time < item.range.end {
            let start = pixelPoint(item.start, in: bounds)
            let end = pixelPoint(item.end, in: bounds)
            let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                              width: abs(end.x - start.x), height: abs(end.y - start.y)).integral.intersection(bounds)
            switch item.kind {
            case .cover, .highlight, .blur, .spotlight:
                guard !rect.isEmpty else { continue }
                image = applyRegion(item, in: rect, over: image, bounds: bounds)
            case .outline, .arrow, .text:
                if let overlay = shape(item, from: start, to: end, rect: rect, bounds: bounds) {
                    image = overlay.composited(over: image).cropped(to: bounds)
                }
            }
        }
        return image
    }

    private static func pixelPoint(_ point: CGPoint, in bounds: CGRect) -> CGPoint {
        let x = point.x.isFinite ? min(1, max(0, point.x)) : 0.5
        let y = point.y.isFinite ? min(1, max(0, point.y)) : 0.5
        return CGPoint(x: bounds.minX + bounds.width * x, y: bounds.maxY - bounds.height * y)
    }

    private static func applyRegion(_ item: RecordingAnnotation, in rect: CGRect, over image: CIImage, bounds: CGRect) -> CIImage {
        let overlay: CIImage
        switch item.kind {
        case .cover:
            overlay = CIImage(color: .black).cropped(to: rect)
        case .highlight:
            let color = item.ink.color.copy(alpha: 0.3) ?? item.ink.color
            overlay = CIImage(color: CIColor(cgColor: color)).cropped(to: rect)
        case .blur:
            overlay = image.clampedToExtent().applyingGaussianBlur(sigma: max(8, min(bounds.width, bounds.height) * 0.024))
                .cropped(to: rect)
        case .spotlight:
            let dim = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.65)).cropped(to: bounds)
            return image.cropped(to: rect).composited(over: dim.composited(over: image)).cropped(to: bounds)
        case .text, .outline, .arrow:
            return image
        }
        return overlay.composited(over: image).cropped(to: bounds)
    }

    private static func shape(_ item: RecordingAnnotation, from start: CGPoint, to end: CGPoint,
                              rect: CGRect, bounds: CGRect) -> CIImage? {
        let scale = min(bounds.width, bounds.height)
        let stroke = max(2, scale * 0.006)
        if item.kind == .text { return label(item, at: start, size: max(10, scale * 0.038), bounds: bounds) }
        let tile = rect.insetBy(dx: -stroke * 6, dy: -stroke * 6).integral.intersection(bounds)
        guard !tile.isEmpty, let bitmap = bitmap(size: tile.size) else { return nil }
        bitmap.translateBy(x: -tile.minX, y: -tile.minY)
        bitmap.setStrokeColor(item.ink.color)
        bitmap.setLineWidth(stroke)
        bitmap.setLineCap(.round)
        bitmap.setLineJoin(.round)
        if item.kind == .outline {
            bitmap.stroke(rect)
        } else {
            let head = min(stroke * 5, hypot(end.x - start.x, end.y - start.y) * 0.45)
            let angle = atan2(end.y - start.y, end.x - start.x)
            bitmap.move(to: start)
            bitmap.addLine(to: end)
            for offset in [-CGFloat.pi / 6, CGFloat.pi / 6] {
                bitmap.move(to: end)
                bitmap.addLine(to: CGPoint(x: end.x - cos(angle + offset) * head, y: end.y - sin(angle + offset) * head))
            }
            bitmap.strokePath()
        }
        return image(from: bitmap, at: tile.origin)
    }

    private static func label(_ item: RecordingAnnotation, at point: CGPoint, size: CGFloat, bounds: CGRect) -> CIImage? {
        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil)
            ?? CTFontCreateWithName("HelveticaNeue-Medium" as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): item.ink.color,
        ]
        let contents = String(item.text.prefix(240))
        guard !contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let raw = CTLineCreateWithAttributedString(NSAttributedString(string: contents, attributes: attributes))
        let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
        let padding = size * 0.42
        let limit = bounds.width * 0.85
        let line = CTLineGetTypographicBounds(raw, nil, nil, nil) > limit
            ? CTLineCreateTruncatedLine(raw, limit, .end, ellipsis) ?? ellipsis
            : raw
        let width = ceil(CTLineGetTypographicBounds(line, nil, nil, nil) + padding * 2)
        let height = ceil(CTFontGetAscent(font) + CTFontGetDescent(font) + padding * 2)
        guard let bitmap = bitmap(size: CGSize(width: width, height: height)) else { return nil }
        bitmap.setFillColor(CGColor(gray: 0.04, alpha: 0.9))
        bitmap.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: width, height: height),
                              cornerWidth: padding, cornerHeight: padding, transform: nil))
        bitmap.fillPath()
        bitmap.textPosition = CGPoint(x: padding, y: padding + CTFontGetDescent(font))
        CTLineDraw(line, bitmap)
        return image(from: bitmap, at: CGPoint(x: max(bounds.minX, min(point.x, bounds.maxX - width)),
                                                y: max(bounds.minY, min(point.y - height, bounds.maxY - height))))
    }

    private static func bitmap(size: CGSize) -> CGContext? {
        CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    private static func image(from context: CGContext, at point: CGPoint) -> CIImage? {
        context.makeImage().map {
            CIImage(cgImage: $0).transformed(by: CGAffineTransform(translationX: point.x, y: point.y))
        }
    }
}
