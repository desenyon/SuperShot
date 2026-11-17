import Foundation
import CoreGraphics
import CoreText
import Document
import Render
import Recognition
import Export

@main struct Benchmark {
    static func main() async throws {
        let width = 5120, height = 2880
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0.96, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 36, nil), NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.1, alpha: 1)]
        for row in 0..<24 {
            context.textPosition = CGPoint(x: 80, y: 100 + row * 108)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: "SuperShot local capture study / row \(row + 1) / immutable pixels and editable layers", attributes: attributes)), context)
        }
        let image = context.makeImage()!
        var document = CaptureDocument(original: try ImageExport.encode(image), width: width, height: height)
        for index in 0..<200 {
            document.layers.append(Layer(kind: index.isMultiple(of: 2) ? .rectangle : .arrow, rect: CGRect(x: (index * 149) % 4500, y: (index * 113) % 2500, width: 240, height: 160), color: RGBA(red: 0.85, green: 0.2, blue: 0.3)))
        }
        for scale in [2200.0 / Double(width), 1.0] {
            var samples: [Double] = []
            for _ in 0..<5 {
                let start = ContinuousClock.now
                let output = try autoreleasepool { try DocumentRenderer.render(document, scale: scale) }
                let elapsed = start.duration(to: .now)
                samples.append(Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15)
                precondition(output.width == Int(ceil(Double(width) * scale)))
            }
            print("render_200_vector_layers_width_\(Int(Double(width) * scale))_ms: \(samples)")
        }
        let service = RecognitionService()
        for accurate in [false, true, false, true] {
            let start = ContinuousClock.now
            let result = try await service.recognize(image, accurate: accurate)
            let elapsed = start.duration(to: .now)
            print("ocr_5120x2880_accurate_\(accurate)_ms: \(Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15), regions: \(result.text.count)")
        }
    }
}
