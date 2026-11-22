import Foundation
import CoreGraphics
import CoreText
import CoreImage
import ImageIO
import Document

// NSCache synchronizes its own access; values are immutable CGImages. Both the
// encoded source and decoded pixels count toward the eviction budget.
private final class DecodedImageCache: @unchecked Sendable {
    private final class Entry: NSObject {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }
    private let cache = NSCache<NSData, Entry>()
    private let budget = 128 * 1024 * 1024
    init() { cache.totalCostLimit = budget; cache.countLimit = 8 }
    func image(for data: Data) -> CGImage? { cache.object(forKey: data as NSData)?.image }
    func insert(_ image: CGImage, for data: Data) {
        let cost = image.bytesPerRow * image.height + data.count
        guard cost <= budget else { return }
        cache.setObject(Entry(image), forKey: data as NSData, cost: cost)
    }
}

public enum DocumentRenderer {
    private static let effectsContext = CIContext(options:[.cacheIntermediates:false])
    private static let decodedImages = DecodedImageCache()
    public struct Layout: Sendable {
        public let size: CGSize
        public let content: CGRect
        public let crop: CGRect
    }
    public enum Error: LocalizedError {
        case invalidImage, tooLarge
        public var errorDescription: String? { self == .tooLarge ? "The image is too large to render. Reduce the padding or output size." : "This image could not be decoded." }
    }
    public static func layout(_ document: CaptureDocument) -> Layout {
        let crop = document.visibleBounds
        let b = document.backdrop
        let padding = b.fill == .none ? 0 : max(0, b.padding) + max(0, b.inset ?? 0)
        var size = CGSize(width: crop.width + padding * 2, height: crop.height + padding * 2)
        if b.fill != .none, b.ratio > 0 {
            if size.width / size.height < b.ratio { size.width = size.height * b.ratio }
            else { size.height = size.width / b.ratio }
        }
        size.width = ceil(size.width); size.height = ceil(size.height)
        return Layout(size: size, content: CGRect(x: (size.width - crop.width) * b.alignmentX, y: (size.height - crop.height) * b.alignmentY, width: crop.width, height: crop.height), crop: crop)
    }
    public static func decode(_ data: Data) -> CGImage? {
        if let cached = decodedImages.image(for: data) { return cached }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let properties=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any]
        let pixelWidth=properties?[kCGImagePropertyPixelWidth] as? Int ?? 0,pixelHeight=properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard pixelWidth>0,pixelHeight>0,pixelWidth<=32768,pixelHeight<=32768,pixelWidth*pixelHeight<=160_000_000 else{return nil}
        let orientation=properties?[kCGImagePropertyOrientation] as? Int ?? 1
        if orientation != 1 {
            let width=properties?[kCGImagePropertyPixelWidth] as? Int ?? 1,height=properties?[kCGImagePropertyPixelHeight] as? Int ?? 1
            let image = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:max(width,height),kCGImageSourceShouldCacheImmediately:true] as CFDictionary)
            if let image { decodedImages.insert(image, for: data) }
            return image
        }
        let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        if let image { decodedImages.insert(image, for: data) }
        return image
    }
    public static func render(_ document: CaptureDocument, scale: Double = 1) throws -> CGImage {
        guard let base = decode(document.processedBase ?? document.original) else { throw Error.invalidImage }
        let layout = layout(document)
        let scale = max(0.01, min(4, scale))
        guard layout.size.width.isFinite,layout.size.height.isFinite,layout.size.width*scale<=32768,layout.size.height*scale<=32768 else {throw Error.tooLarge}
        let width = Int(ceil(layout.size.width * scale)), height = Int(ceil(layout.size.height * scale))
        guard width > 0, height > 0, width <= 32768, height <= 32768, width * height <= 160_000_000 else { throw Error.tooLarge }
        // One top-left-coordinate compositor is used for both the canvas and export.
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: document.preserveColorProfile == true && base.colorSpace?.model == .rgb ? (base.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!) : CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw Error.tooLarge }
        context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: scale, y: -scale)
        context.interpolationQuality = .high
        let bounds = CGRect(origin: .zero, size: layout.size)
        drawBackdrop(document.backdrop, bounds: bounds, context: context)
        let content = layout.content
        let styled = document.backdrop.fill != .none
        let inset = styled ? max(0, document.backdrop.inset ?? 0) : 0
        let frame = content.insetBy(dx: -inset, dy: -inset)
        let radius = styled ? min(document.backdrop.radius, min(frame.width, frame.height) / 2) : 0
        let path = CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
        if styled, document.backdrop.shadow > 0 {
            // Two passes: a wide ambient shadow and a tight contact shadow. Both scale with the image.
            let unit = max(1, min(frame.width, frame.height) / 700)
            for (offset, blur, strength) in [(18.0, 48.0, 0.75), (3.0, 8.0, 0.45)] {
                context.saveGState()
                context.setShadow(offset: CGSize(width: 0, height: -offset * unit * scale), blur: blur * unit * scale, color: CGColor(gray: 0, alpha: document.backdrop.shadow * strength))
                context.setFillColor(CGColor(gray: 0, alpha: 1)); context.addPath(path); context.fillPath()
                context.restoreGState()
            }
        }
        context.saveGState(); context.addPath(path); context.clip()
        if inset > 0 {
            context.setFillColor(sample(base, at: CGPoint(x: layout.crop.minX + 1, y: layout.crop.minY + 1)).cgColor); context.fill(frame)
        }
        context.clip(to: content)
        context.translateBy(x: content.minX - layout.crop.minX, y: content.minY - layout.crop.minY)
        drawImage(base, in: document.imageBounds, context: context)
        for layer in document.layers {
            try Task.checkCancellation()
            draw(layer, document: document, layout: layout, scale: scale, context: context)
        }
        context.restoreGState()
        if let watermark = document.backdrop.watermark {
            drawWatermark(watermark, within: bounds, context: context)
        }
        guard let result = context.makeImage() else { throw Error.invalidImage }
        return result
    }

    private static func drawWatermark(_ watermark: ImageWatermark, within bounds: CGRect, context: CGContext) {
        let value = watermark.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !value.isEmpty, watermark.opacity > 0, bounds.width >= 40, bounds.height >= 24 else { return }
        let fontSize = max(9, min(72, min(bounds.width, bounds.height) * 0.027))
        let margin = fontSize * 0.8
        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, fontSize, nil)
            ?? CTFontCreateWithName("HelveticaNeue-Medium" as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)
        ]
        let fullLine = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: attributes))
        let available = max(1, bounds.width - margin * 4)
        let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
        let line = CTLineCreateTruncatedLine(fullLine, available, .end, ellipsis) ?? fullLine
        let width = min(available, CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))) + margin * 2
        let height = min(bounds.height - margin, fontSize * 1.75)
        let x = margin + max(0, bounds.width - width - margin * 2) * watermark.anchor.x
        let y = margin / 2 + (bounds.height - height - margin) * watermark.anchor.y
        let rect = CGRect(x: x, y: y, width: width, height: height)
        context.saveGState()
        context.clip(to: rect)
        context.setAlpha(watermark.opacity)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setFillColor(CGColor(gray: 0, alpha: 0.78))
        context.addPath(CGPath(roundedRect: rect, cornerWidth: margin / 2, cornerHeight: margin / 2, transform: nil))
        context.fillPath()
        context.translateBy(x: rect.minX + margin, y: rect.midY + CTFontGetCapHeight(font) / 2)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.endTransparencyLayer()
        context.restoreGState()
    }
    private static func drawBackdrop(_ backdrop: Backdrop, bounds: CGRect, context: CGContext) {
        guard backdrop.fill != .none else { return }
        context.setFillColor(backdrop.color.cgColor); context.fill(bounds)
        if backdrop.fill == .gradient {
            let stops = backdrop.gradientStops
            let locations = stops.indices.map { CGFloat($0) / CGFloat(max(1, stops.count - 1)) }
            if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: stops.map(\.cgColor) as CFArray, locations: locations) {
                var start = bounds.origin, end = CGPoint(x: bounds.maxX, y: bounds.maxY)
                if let angle = backdrop.angle {
                    let radians = angle * .pi / 180, dx = cos(radians), dy = sin(radians)
                    let half = (abs(bounds.width * dx) + abs(bounds.height * dy)) / 2
                    start = CGPoint(x: bounds.midX - dx * half, y: bounds.midY - dy * half)
                    end = CGPoint(x: bounds.midX + dx * half, y: bounds.midY + dy * half)
                }
                context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
        }
        if backdrop.fill == .wallpaper, let data = backdrop.wallpaper, let image = decode(data) {
            var displayImage = image
            if backdrop.blur > 0 {
                let ci = CIImage(cgImage: image).clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: backdrop.blur])
                displayImage = effectsContext.createCGImage(ci, from: CGRect(x: 0, y: 0, width: image.width, height: image.height)) ?? image
            }
            let fit = max(bounds.width / CGFloat(image.width), bounds.height / CGFloat(image.height))
            let size = CGSize(width: CGFloat(image.width) * fit, height: CGFloat(image.height) * fit)
            drawImage(displayImage, in: CGRect(x: bounds.midX-size.width/2, y: bounds.midY-size.height/2, width: size.width, height: size.height), context: context)
        }
    }
    /// Paints layers into a context that already uses image pixel coordinates with a top-left origin.
    /// The canvas uses this for selected layers, so they follow the pointer without a new raster.
    /// Layers that sample the pixels beneath them (blur, pixelate, magnifier) need a bitmap context and draw nothing here.
    public static func drawLive(_ layers: [Layer], document: CaptureDocument, scale: Double, context: CGContext) {
        let layout = layout(document)
        for layer in layers { draw(layer, document: document, layout: layout, scale: scale, context: context) }
    }
    private static func draw(_ layer: Layer, document: CaptureDocument, layout: Layout, scale: Double, context: CGContext) {
        context.saveGState(); defer { context.restoreGState() }
        context.setAlpha(layer.opacity); context.setStrokeColor(layer.color.cgColor); context.setFillColor(layer.color.cgColor)
        context.setLineWidth(layer.stroke); context.setLineCap(.round); context.setLineJoin(.round)
        let rect = layer.rect.standardized
        if layer.rotation != 0 {
            context.translateBy(x: rect.midX, y: rect.midY); context.rotate(by: layer.rotation * .pi / 180); context.translateBy(x: -rect.midX, y: -rect.midY)
        }
        switch layer.kind {
        case .rectangle: layer.filled ? context.fill(rect) : context.stroke(rect)
        case .oval: layer.filled ? context.fillEllipse(in: rect) : context.strokeEllipse(in: rect)
        case .line, .arrow, .ruler:
            let a = layer.points.first ?? rect.origin
            let b = layer.points.last ?? CGPoint(x: rect.maxX, y: rect.maxY)
            let bend=layer.arrowBend ?? 0
            let control=CGPoint(x:(a.x+b.x)/2-(b.y-a.y)*bend,y:(a.y+b.y)/2+(b.x-a.x)*bend)
            let filledHead = layer.kind == .arrow && layer.arrowHead == "filled"
            let tangent = bend == 0 ? a : control
            let angle = atan2(b.y-tangent.y, b.x-tangent.x), length = max(16, layer.stroke * 4.5), spread = 0.44
            // A filled head covers the end of the shaft, so stop the shaft inside it to keep the tip sharp.
            let shaftEnd = filledHead ? CGPoint(x: b.x-length*0.72*cos(angle), y: b.y-length*0.72*sin(angle)) : b
            context.move(to: a)
            if layer.kind == .arrow && bend != 0 {context.addQuadCurve(to:shaftEnd,control:control)} else {context.addLine(to:shaftEnd)}
            context.strokePath()
            if layer.kind == .arrow && layer.arrowHead != "none" {
                let p = CGPoint(x: b.x-length*cos(angle-spread), y: b.y-length*sin(angle-spread))
                let q = CGPoint(x: b.x-length*cos(angle+spread), y: b.y-length*sin(angle+spread))
                context.move(to: p); context.addLine(to: b); context.addLine(to: q)
                if filledHead {context.closePath();context.setLineWidth(max(1,layer.stroke*0.35));context.drawPath(using:.fillStroke);context.setLineWidth(layer.stroke)} else {context.strokePath()}
                if layer.arrowHead == "double" {
                    let back=atan2(a.y-control.y,a.x-control.x)
                    context.move(to:CGPoint(x:a.x-length*cos(back-spread),y:a.y-length*sin(back-spread)))
                    context.addLine(to:a);context.addLine(to:CGPoint(x:a.x-length*cos(back+spread),y:a.y-length*sin(back+spread)));context.strokePath()
                }
            }
            if layer.kind == .ruler {
                let length = hypot(b.x-a.x, b.y-a.y)
                text(String(format: "%.0f px · %.1f°", length, atan2(b.y-a.y,b.x-a.x)*180 / .pi), at: CGPoint(x: rect.midX, y: rect.midY-30), size: 20, color: layer.color, context: context)
            }
        case .drawing, .highlighter:
            if layer.kind == .highlighter { context.setAlpha(layer.opacity * 0.32); context.setLineWidth(layer.stroke * 5); context.setBlendMode(.multiply) }
            guard let first = layer.points.first else { return }
            context.move(to: first)
            if layer.points.count > 2 {
                for index in 1..<layer.points.count-1 {
                    let current=layer.points[index],next=layer.points[index+1]
                    context.addQuadCurve(to:CGPoint(x:(current.x+next.x)/2,y:(current.y+next.y)/2),control:current)
                }
                if let last=layer.points.last {context.addLine(to:last)}
            } else {for point in layer.points.dropFirst() { context.addLine(to: point) }}
            context.strokePath()
        case .text:
            if let background=layer.textBackground {let pad=layer.fontSize*0.3,box=rect.insetBy(dx:-pad,dy:-pad*0.45);context.setFillColor(background.cgColor);context.addPath(CGPath(roundedRect:box,cornerWidth:min(layer.fontSize*0.32,box.height/2),cornerHeight:min(layer.fontSize*0.32,box.height/2),transform:nil));context.fillPath();context.setFillColor(layer.color.cgColor)}
            if layer.textOutline == true {context.setLineWidth(max(1,layer.fontSize/14));context.setStrokeColor(CGColor(gray:0,alpha:1));context.setTextDrawingMode(.fillStroke)}
            text(layer.text, at: rect.origin, size: layer.fontSize, color: layer.color, context: context)
        case .counter:
            context.setShadow(offset: CGSize(width: 0, height: -2 * scale), blur: 6 * scale, color: CGColor(gray: 0, alpha: 0.3))
            context.fillEllipse(in: rect)
            context.setShadow(offset: .zero, blur: 0, color: nil)
            context.setStrokeColor(CGColor(gray: 1, alpha: 0.95)); context.setLineWidth(max(2, rect.width * 0.07))
            context.strokeEllipse(in: rect.insetBy(dx: rect.width * 0.035, dy: rect.width * 0.035))
            let luminance = 0.299 * layer.color.red + 0.587 * layer.color.green + 0.114 * layer.color.blue
            text(layer.text, at: CGPoint(x: rect.midX, y: rect.midY), size: min(layer.fontSize, rect.height * 0.5), color: luminance > 0.7 ? .black : .white, context: context, centered: true)
        case .spotlight:
            context.setFillColor(CGColor(gray: 0, alpha: 0.55))
            context.addRect(document.imageBounds); context.addEllipse(in: rect); context.fillPath(using: .evenOdd)
        case .erase: context.fill(rect)
        case .image:
            if let data = layer.imageData, let image = decode(data) { drawImage(image, in: rect, context: context) }
        case .blur, .pixelate, .magnifier:
            guard let snapshot=context.makeImage() else{return}
            let transform=context.ctm
            let center=CGPoint(x:rect.midX,y:rect.midY).applying(transform)
            context.saveGState()
            if layer.kind == .magnifier {context.addEllipse(in:rect)} else {context.addRect(rect)}
            context.clip()
            // Keep the transformed clip, then draw the effect in snapshot/device coordinates.
            // This avoids stretching a clipped sample and keeps rotated effects over their real source pixels.
            context.concatenate(transform.inverted())
            let pixelBounds=CGRect(x:0,y:0,width:snapshot.width,height:snapshot.height)
            if layer.kind == .magnifier {
                context.translateBy(x:-center.x,y:-center.y);context.scaleBy(x:2,y:2)
                context.draw(snapshot,in:pixelBounds)
            } else {
                let filter=layer.kind == .blur ? "CIGaussianBlur":"CIPixellate"
                let key=layer.kind == .blur ? kCIInputRadiusKey:kCIInputScaleKey
                let input=CIImage(cgImage:snapshot)
                let filtered=input.clampedToExtent().applyingFilter(filter,parameters:[key:max(8,layer.stroke*4)*scale])
                if let output=effectsContext.createCGImage(filtered,from:input.extent){context.draw(output,in:pixelBounds)}
            }
            context.restoreGState()
            if layer.kind == .magnifier {context.strokeEllipse(in:rect.insetBy(dx:layer.stroke/2,dy:layer.stroke/2))}

        }
    }
    public static func drawImage(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState(); context.translateBy(x: rect.minX, y: rect.maxY); context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size)); context.restoreGState()
    }
    private static func text(_ value: String, at point: CGPoint, size: Double, color: RGBA, context: CGContext, centered: Bool = false) {
        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil) ?? CTFontCreateWithName("HelveticaNeue-Medium" as CFString, size, nil)
        for (index, line) in value.components(separatedBy: "\n").enumerated() {
            let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor]
            let text = CTLineCreateWithAttributedString(NSAttributedString(string: line, attributes: attributes))
            var origin = CGPoint(x: point.x, y: point.y + size + Double(index)*size*1.25)
            if centered {
                let width = CTLineGetTypographicBounds(text, nil, nil, nil)
                origin = CGPoint(x: point.x - width / 2, y: point.y + CTFontGetCapHeight(font) / 2)
            }
            context.saveGState(); context.translateBy(x: origin.x, y: origin.y); context.scaleBy(x: 1, y: -1); context.textPosition = .zero
            CTLineDraw(text, context); context.restoreGState()
        }
    }
    public static func sample(_ image: CGImage, at point: CGPoint) -> RGBA {
        let x = max(0, min(image.width-1, Int(point.x))), y = max(0, min(image.height-1, Int(point.y)))
        guard let pixel = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else { return .black }
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name:CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        let alpha = Double(bytes[3])/255
        return RGBA(red: alpha > 0 ? Double(bytes[0])/255/alpha : 0, green: alpha > 0 ? Double(bytes[1])/255/alpha : 0, blue: alpha > 0 ? Double(bytes[2])/255/alpha : 0, alpha: alpha)
    }
}

public extension DocumentRenderer {
    /// Ignores low-alpha pixels so a soft system shadow can be trimmed separately from content.
    static func alphaBounds(_ image:CGImage,threshold:UInt8=1)->CGRect? {
        var pixels=[UInt8](repeating:0,count:image.width*image.height*4)
        let ok=pixels.withUnsafeMutableBytes{buffer->Bool in
            guard let context=CGContext(data:buffer.baseAddress,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{return false}
            context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height));return true
        }
        guard ok else{return nil}
        var minX=image.width,minY=image.height,maxX = -1,maxY = -1
        for y in 0..<image.height {for x in 0..<image.width where pixels[(y*image.width+x)*4+3]>=threshold {minX=min(minX,x);minY=min(minY,y);maxX=max(maxX,x);maxY=max(maxY,y)}}
        return maxX<0 ? nil:CGRect(x:minX,y:minY,width:maxX-minX+1,height:maxY-minY+1)
    }
    /// Content bounds estimated against the corner color. Intended for uneven blank margins.
    static func balancedBounds(_ image:CGImage)->CGRect? {
        let width=min(320,image.width),height=max(1,Int(Double(image.height)*Double(width)/Double(image.width)))
        guard height<=32000 else{return nil}
        var pixels=[UInt8](repeating:0,count:width*height*4)
        pixels.withUnsafeMutableBytes{buffer in
            let context=CGContext(data:buffer.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
        }
        let corner=[Int(pixels[0]),Int(pixels[1]),Int(pixels[2])]
        var minX=width,minY=height,maxX = -1,maxY = -1
        for y in 0..<height {for x in 0..<width {
            let i=(y*width+x)*4
            let delta=abs(Int(pixels[i])-corner[0])+abs(Int(pixels[i+1])-corner[1])+abs(Int(pixels[i+2])-corner[2])
            if delta>70 && pixels[i+3]>20 {minX=min(minX,x);minY=min(minY,y);maxX=max(maxX,x);maxY=max(maxY,y)}
        }}
        guard maxX>minX,maxY>minY else{return nil}
        let factor=CGFloat(image.width)/CGFloat(width)
        return CGRect(x:CGFloat(minX)*factor,y:CGFloat(minY)*factor,width:CGFloat(maxX-minX+1)*factor,height:CGFloat(maxY-minY+1)*factor).insetBy(dx:-12,dy:-12).intersection(CGRect(x:0,y:0,width:image.width,height:image.height))
    }
}
