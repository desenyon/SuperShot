import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Document
@testable import Render

struct RenderTests {
    func fixture() throws -> CaptureDocument {
        let context = CGContext(data: nil, width: 80, height: 60, bitsPerComponent: 8, bytesPerRow: 320, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 30, width: 80, height: 30))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 80, height: 30))
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, context.makeImage()!, nil); CGImageDestinationFinalize(dest)
        return CaptureDocument(original: data as Data, width: 80, height: 60)
    }
    @Test func topLeftCropStaysRedAndOriginalStaysUntouched() throws {
        var doc = try fixture(); let original = doc.original
        doc.crop = CGRect(x: 0, y: 0, width: 40, height: 20)
        let image = try DocumentRenderer.render(doc)
        #expect(image.width == 40 && image.height == 20)
        let color = DocumentRenderer.sample(image, at: CGPoint(x: 10, y: 10))
        #expect(color.red > 0.95 && color.blue < 0.05)
        #expect(doc.original == original)
    }
    @Test func backdropAndAnnotationRenderInExportCoordinates() throws {
        var doc = try fixture()
        doc.backdrop.fill = .solid; doc.backdrop.padding = 10; doc.backdrop.radius = 0; doc.backdrop.shadow = 0
        doc.backdrop.color = RGBA(red: 0, green: 1, blue: 0)
        doc.layers = [Layer(kind: .rectangle, rect: CGRect(x: 10, y: 10, width: 20, height: 20), color: .white, filled: true)]
        let image = try DocumentRenderer.render(doc)
        #expect(image.width == 100 && image.height == 80)
        #expect(DocumentRenderer.sample(image, at: CGPoint(x: 2, y: 2)).green > 0.95)
        #expect(DocumentRenderer.sample(image, at: CGPoint(x: 25, y: 25)).red > 0.95)
        #expect(DocumentRenderer.sample(image, at: CGPoint(x: 25, y: 25)).blue > 0.95)
    }
    @Test func pngSnapshotIsRepeatable() throws {
        var doc = try fixture()
        doc.layers = [Layer(kind: .line, rect: CGRect(x: 4, y: 6, width: 60, height: 40), points: [CGPoint(x: 4, y: 6), CGPoint(x: 64, y: 46)], color: .white)]
        let first = try DocumentRenderer.render(doc)
        let second = try DocumentRenderer.render(doc)
        #expect(first.dataProvider?.data as Data? == second.dataProvider?.data as Data?)
    }
    @Test func watermarkCompositesInTheChosenOutputCorner() throws {
        var document = try fixture()
        let base = try DocumentRenderer.render(document)
        document.backdrop.watermark = ImageWatermark(text: "Review", anchor: CGPoint(x: 0, y: 0), opacity: 0.8)
        let result = try DocumentRenderer.render(document)
        let transparent = try #require(DocumentRenderer.decode(document.original))
        #expect(result.width == base.width && result.height == base.height)
        #expect(result.dataProvider?.data as Data? != base.dataProvider?.data as Data?)
        #expect(DocumentRenderer.sample(result, at: CGPoint(x: 75, y: 50)) == DocumentRenderer.sample(transparent, at: CGPoint(x: 75, y: 50)))
        document.backdrop.watermark?.opacity = 0
        let hidden = try DocumentRenderer.render(document)
        #expect(hidden.dataProvider?.data as Data? == base.dataProvider?.data as Data?)
    }
}

extension RenderTests {
    @Test func cachedDecodeKeepsDifferentSourcesIndependent() throws {
        let document = try fixture()
        _ = try #require(DocumentRenderer.decode(document.original))
        var changed = document
        changed.layers = [Layer(kind: .rectangle, rect: document.imageBounds, color: .white, filled: true)]
        let white = try DocumentRenderer.render(changed), data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, white, nil)
        #expect(CGImageDestinationFinalize(destination))
        let other = try #require(DocumentRenderer.decode(data as Data))
        #expect(DocumentRenderer.sample(other, at: CGPoint(x: 10, y: 50)).red > 0.95)
        let again = try #require(DocumentRenderer.decode(document.original))
        let sample = DocumentRenderer.sample(again, at: CGPoint(x: 10, y: 50))
        #expect(sample.blue > 0.95 && sample.red < 0.05)
    }
    @Test func backdropMatchesIndependentGoldenSnapshot() throws {
        var doc=try fixture();doc.backdrop.fill = .solid;doc.backdrop.padding=10;doc.backdrop.radius=0;doc.backdrop.shadow=0;doc.backdrop.color=RGBA(red:0,green:1,blue:0)
        doc.layers=[Layer(kind:.rectangle,rect:CGRect(x:10,y:10,width:20,height:20),color:.white,filled:true)]
        let actual=try DocumentRenderer.render(doc)
        let url=try #require(Bundle.module.url(forResource:"solid-rectangle",withExtension:"png",subdirectory:"Fixtures"))
        let expected=try #require(DocumentRenderer.decode(Data(contentsOf:url)))
        for y in 0..<80 {for x in 0..<100 {
            let a=DocumentRenderer.sample(actual,at:CGPoint(x:x,y:y)),b=DocumentRenderer.sample(expected,at:CGPoint(x:x,y:y))
            #expect(abs(a.red-b.red)<0.01 && abs(a.green-b.green)<0.01 && abs(a.blue-b.blue)<0.01)
        }}
    }
    @Test func rotatedMagnifierUsesPixelsAtItsVisiblePosition() throws {
        var doc=try fixture()
        doc.layers=[Layer(kind:.magnifier,rect:CGRect(x:10,y:0,width:20,height:20),color:.white,stroke:1,rotation:90)]
        let image=try DocumentRenderer.render(doc),center=DocumentRenderer.sample(image,at:CGPoint(x:20,y:10))
        #expect(center.red>0.95 && center.blue<0.05)
        #expect(DocumentRenderer.sample(image,at:CGPoint(x:70,y:50)).blue>0.95)
    }
    @Test func partiallyClippedBlurDoesNotStretchPixelsOutsideItsRegion() throws {
        var doc=try fixture();doc.crop=CGRect(x:20,y:10,width:40,height:40)
        doc.layers=[Layer(kind:.blur,rect:CGRect(x:0,y:0,width:30,height:20),stroke:1)]
        let image=try DocumentRenderer.render(doc)
        #expect(image.width == 40 && image.height == 40)
        #expect(DocumentRenderer.sample(image,at:CGPoint(x:30,y:35)).blue>0.95)
    }
}

extension RenderTests {
    @Test func gradientStopsAndAngleControlTheBackdrop() throws {
        var doc = try fixture()
        doc.backdrop.fill = .gradient; doc.backdrop.padding = 40; doc.backdrop.shadow = 0
        doc.backdrop.stops = [RGBA(red: 1, green: 0, blue: 0), RGBA(red: 0, green: 1, blue: 0), RGBA(red: 0, green: 0, blue: 1)]
        doc.backdrop.angle = 0
        let image = try DocumentRenderer.render(doc)
        // Left to right: red, then green in the middle, then blue.
        #expect(DocumentRenderer.sample(image, at: CGPoint(x: 1, y: 5)).red > 0.9)
        #expect(DocumentRenderer.sample(image, at: CGPoint(x: 80, y: 5)).green > 0.9)
        #expect(DocumentRenderer.sample(image, at: CGPoint(x: 158, y: 5)).blue > 0.9)
    }
    @Test func insetAddsAFrameInTheImageEdgeColor() throws {
        var doc = try fixture()
        doc.backdrop.fill = .solid; doc.backdrop.padding = 10; doc.backdrop.radius = 0; doc.backdrop.shadow = 0
        doc.backdrop.color = RGBA(red: 0, green: 1, blue: 0); doc.backdrop.inset = 6
        #expect(DocumentRenderer.layout(doc).size == CGSize(width: 112, height: 92))
        let image = try DocumentRenderer.render(doc)
        // Backdrop, then the frame in the image's top-left color (red), then the image itself.
        #expect(DocumentRenderer.sample(image, at: CGPoint(x: 5, y: 5)).green > 0.95)
        #expect(DocumentRenderer.sample(image, at: CGPoint(x: 13, y: 46)).red > 0.95)
        #expect(DocumentRenderer.sample(image, at: CGPoint(x: 30, y: 70)).blue > 0.95)
    }
    @Test func projectsWithoutNewBackdropFieldsStillOpen() throws {
        let doc = try fixture()
        var json = try #require(JSONSerialization.jsonObject(with: ProjectFile.encode(doc)) as? [String: Any])
        var document = try #require(json["document"] as? [String: Any])
        var backdrop = try #require(document["backdrop"] as? [String: Any])
        for key in ["stops", "angle", "inset"] { backdrop[key] = nil }
        document["backdrop"] = backdrop; json["document"] = document
        let decoded = try ProjectFile.decode(JSONSerialization.data(withJSONObject: json))
        #expect(decoded.backdrop.inset == nil && decoded.backdrop.gradientStops.count == 2)
    }
}
