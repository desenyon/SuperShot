import Foundation
import CoreGraphics

public struct RGBA: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }
    public static let white = RGBA(red: 1, green: 1, blue: 1)
    public static let black = RGBA(red: 0, green: 0, blue: 0)
    public var cgColor: CGColor { CGColor(red: red, green: green, blue: blue, alpha: alpha) }
    public var hex: String {
        String(format: "#%02X%02X%02X", Int(max(0, min(1, red)) * 255), Int(max(0, min(1, green)) * 255), Int(max(0, min(1, blue)) * 255))
    }
}

public enum LayerKind: String, Codable, CaseIterable, Sendable {
    case rectangle, oval, line, arrow, drawing, highlighter, counter, text
    case spotlight, magnifier, blur, pixelate, erase, ruler, image
}

/// Coordinates are in original image pixels, with the origin at the top left.
public struct Layer: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: LayerKind
    public var rect: CGRect
    public var points: [CGPoint]
    public var color: RGBA
    public var stroke: Double
    public var opacity: Double
    public var filled: Bool
    public var text: String
    public var fontSize: Double
    public var rotation: Double
    public var imageData: Data?
    public var arrowHead: String?
    public var arrowBend: Double?
    public var textBackground: RGBA?
    public var textOutline: Bool?
    public init(id: UUID = UUID(), kind: LayerKind, rect: CGRect, points: [CGPoint] = [], color: RGBA = RGBA(red: 1, green: 0.28, blue: 0.29), stroke: Double = 4, opacity: Double = 1, filled: Bool = false, text: String = "", fontSize: Double = 28, rotation: Double = 0, imageData: Data? = nil) {
        self.id=id; self.kind=kind; self.rect=rect; self.points=points; self.color=color; self.stroke=stroke; self.opacity=opacity; self.filled=filled; self.text=text; self.fontSize=fontSize; self.rotation=rotation; self.imageData=imageData
    }
    public mutating func translate(x: CGFloat, y: CGFloat) {
        rect.origin.x += x; rect.origin.y += y
        points = points.map { CGPoint(x: $0.x + x, y: $0.y + y) }
    }
    public mutating func resize(to newRect: CGRect) {
        let sx = newRect.width / max(1, rect.width), sy = newRect.height / max(1, rect.height)
        points = points.map { CGPoint(x: newRect.minX + ($0.x - rect.minX) * sx, y: newRect.minY + ($0.y - rect.minY) * sy) }
        rect = newRect
    }
}

public struct Backdrop: Codable, Equatable, Sendable {
    public enum Fill: String, Codable, CaseIterable, Sendable { case none, solid, gradient, wallpaper }
    public var fill: Fill = .none
    public var color = RGBA(red: 0.76, green: 0.84, blue: 0.94)
    public var secondaryColor = RGBA(red: 0.39, green: 0.52, blue: 0.70)
    public var padding: Double = 64
    public var radius: Double = 16
    public var shadow: Double = 0.28
    public var ratio: Double = 0
    public var alignmentX: Double = 0.5
    public var alignmentY: Double = 0.5
    public var wallpaper: Data?
    public var blur: Double = 0
    /// Gradient stops. When nil the gradient runs from `color` to `secondaryColor`.
    public var stops: [RGBA]?
    /// Gradient direction in degrees (0 = left to right, 90 = top to bottom). Nil keeps the corner-to-corner default.
    public var angle: Double?
    /// Width of a frame around the image, filled with the image's edge color.
    public var inset: Double?
    public init() {}
    public var gradientStops: [RGBA] { (stops?.count ?? 0) >= 2 ? stops! : [color, secondaryColor] }
}

public struct CaptureDocument: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public let original: Data
    public let width: Int
    public let height: Int
    public var scale: Double
    public var date: Date
    public var source: String
    public var preserveColorProfile: Bool?
    public var metadata: [String: String]?
    public var processedBase: Data?
    public var layers: [Layer] = []
    public var crop: CGRect?
    public var backdrop = Backdrop()
    public init(original: Data, width: Int, height: Int, scale: Double = 1, source: String = "Screenshot", date: Date = Date()) {
        self.id=UUID(); self.original=original; self.width=width; self.height=height; self.scale=scale; self.source=source; self.date=date
    }
    public var imageBounds: CGRect { CGRect(x: 0, y: 0, width: width, height: height) }
    public var visibleBounds: CGRect {
        guard let crop else { return imageBounds }
        let clipped = crop.standardized.integral.intersection(imageBounds)
        return clipped.isEmpty || clipped.isNull ? imageBounds : clipped
    }
}

public struct DocumentHistory: Sendable {
    public private(set) var document: CaptureDocument
    private var past: [CaptureDocument] = []
    private var future: [CaptureDocument] = []
    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }
    public init(document: CaptureDocument) { self.document = document }
    public mutating func change(_ update: (inout CaptureDocument) -> Void) {
        var next = document; update(&next)
        guard next != document else { return }
        past.append(document); future.removeAll(); document = next
    }
    public mutating func undo() {
        guard let previous = past.popLast() else { return }
        future.append(document); document = previous
    }
    public mutating func redo() {
        guard let next = future.popLast() else { return }
        past.append(document); document = next
    }
}

public enum ProjectFile {
    private struct Envelope: Codable { var version: Int; var document: CaptureDocument }
    public enum Error: LocalizedError { case unsupportedVersion, invalidDimensions, invalidGeometry
        public var errorDescription: String? {
            switch self {
            case .unsupportedVersion: "This project was created by a newer version of SuperShot."
            case .invalidDimensions: "The project has invalid image dimensions."
            case .invalidGeometry: "The project contains invalid editing values."
            }
        }
    }
    public static func encode(_ document: CaptureDocument) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Envelope(version: 1, document: document))
    }
    public static func decode(_ data: Data) throws -> CaptureDocument {
        struct Header: Decodable { var version: Int }
        let decoder = JSONDecoder()
        guard try decoder.decode(Header.self, from: data).version == 1 else { throw Error.unsupportedVersion }
        let doc = try decoder.decode(Envelope.self, from: data).document
        guard doc.width > 0, doc.height > 0, doc.width <= 32768, doc.height <= 32768 else { throw Error.invalidDimensions }
        let b=doc.backdrop
        guard doc.width*doc.height<=160_000_000,doc.scale.isFinite,doc.scale>=0.1,doc.scale<=8 else {throw Error.invalidDimensions}
        guard b.padding.isFinite,(0...4096).contains(b.padding),b.radius.isFinite,(0...4096).contains(b.radius),b.shadow.isFinite,(0...1).contains(b.shadow),b.ratio.isFinite,(b.ratio == 0 || (0.01...100).contains(b.ratio)),b.alignmentX.isFinite,(0...1).contains(b.alignmentX),b.alignmentY.isFinite,(0...1).contains(b.alignmentY),b.blur.isFinite,(0...1000).contains(b.blur),(b.inset.map{$0.isFinite && (0...1024).contains($0)} ?? true),(b.angle.map{$0.isFinite && abs($0)<=3600} ?? true),(b.stops?.count ?? 0)<=16 else {throw Error.invalidGeometry}
        func valid(_ rect:CGRect)->Bool {[rect.origin.x,rect.origin.y,rect.width,rect.height].allSatisfy{$0.isFinite && abs($0)<1_000_000}}
        guard doc.crop.map(valid) ?? true,doc.layers.allSatisfy({layer in
            valid(layer.rect) && layer.points.allSatisfy{$0.x.isFinite && $0.y.isFinite && abs($0.x)<1_000_000 && abs($0.y)<1_000_000} && layer.stroke.isFinite && (0...4096).contains(layer.stroke) && layer.opacity.isFinite && (0...1).contains(layer.opacity) && layer.fontSize.isFinite && (1...4096).contains(layer.fontSize) && layer.rotation.isFinite && (layer.arrowBend.map{$0.isFinite && abs($0)<=10} ?? true)
        }) else {throw Error.invalidGeometry}
        let crop=doc.visibleBounds,padding=b.fill == .none ? 0:b.padding+(b.inset ?? 0)
        var outputWidth=crop.width+padding*2,outputHeight=crop.height+padding*2
        if b.fill != .none && b.ratio>0 {if outputWidth/outputHeight<b.ratio {outputWidth=outputHeight*b.ratio}else{outputHeight=outputWidth/b.ratio}}
        guard outputWidth.isFinite,outputHeight.isFinite,outputWidth>0,outputHeight>0,outputWidth<=32768,outputHeight<=32768,outputWidth*outputHeight<=160_000_000 else{throw Error.invalidGeometry}
        return doc
    }
}

public struct BackdropPreset: Codable, Equatable, Identifiable, Sendable {
    public let id:UUID
    public var name:String
    public var backdrop:Backdrop
    public init(id:UUID=UUID(),name:String,backdrop:Backdrop){self.id=id;self.name=name;self.backdrop=backdrop}
}

public extension Layer {
    func contains(_ point:CGPoint,tolerance:CGFloat=6)->Bool {
        let angle = -rotation * .pi / 180,dx=point.x-rect.midX,dy=point.y-rect.midY
        let local=CGPoint(x:rect.midX+dx*cos(angle)-dy*sin(angle),y:rect.midY+dx*sin(angle)+dy*cos(angle))
        if [.line,.arrow,.ruler,.drawing,.highlighter].contains(kind),points.count>=2 {
            let radius=max(tolerance,stroke*(kind == .highlighter ? 2.5:0.5))
            for index in 1..<points.count {
                let a=points[index-1],b=points[index],vx=b.x-a.x,vy=b.y-a.y,length=vx*vx+vy*vy
                let t=length>0 ? max(0,min(1,((local.x-a.x)*vx+(local.y-a.y)*vy)/length)):0
                if hypot(local.x-a.x-t*vx,local.y-a.y-t*vy)<=radius{return true}
            }
            return false
        }
        if kind == .oval || kind == .counter || kind == .magnifier {
            let rx=max(1,rect.width/2+tolerance),ry=max(1,rect.height/2+tolerance)
            return pow((local.x-rect.midX)/rx,2)+pow((local.y-rect.midY)/ry,2)<=1
        }
        return rect.insetBy(dx:-tolerance,dy:-tolerance).contains(local)
    }
}
