import Foundation
import AI
import CoreGraphics
import Document
import Recognition
import Render

/// A region is anchored to the document the user saw when selecting it.
public struct AskRegion: Identifiable, Sendable {
    public let id = UUID()
    let document: CaptureDocument
    public let rect: CGRect
    let number: Int
    public var label: String { "Region \(number) · \(Int(rect.width)) × \(Int(rect.height))" }
}

struct AskCapture: Sendable {
    let document: CaptureDocument
    let image: CGImage
    let recognition: RecognitionResult
    let candidates: [RedactionCandidate]

    static func prepare(_ document: CaptureDocument, recognize: Bool) async throws -> Self {
        let image = try await Task.detached(priority: .userInitiated) { try DocumentRenderer.render(document) }.value
        try Task.checkCancellation()
        let result = recognize ? try await RecognitionService().recognize(image, accurate: true) : RecognitionResult()
        return Self(document: document, image: image, recognition: result, candidates: SensitiveContent.candidates(in: result))
    }

    func context(redact: Bool, includeText: Bool) throws -> AssistantContext {
        let source = document.source.components(separatedBy: " — ")
        let title = source.count > 1 ? source.dropFirst().joined(separator: " — ") : nil
        func metadata(_ value: String?) -> String? { value.map { redact ? Self.coverSensitiveLines($0) : $0 } }
        let text = recognition.text.filter { line in
            !redact || !candidates.contains { $0.rect.intersects(line.rect) }
        }.map(\.text).joined(separator: "\n")
        return AssistantContext(image: try pixels(redact: redact), recognizedText: includeText ? text : nil,
                                appName: metadata(source.first), windowTitle: metadata(title))
    }

    /// Titles and excerpts can repeat the same sensitive text as the pixels.
    static func coverSensitiveLines(_ value: String) -> String {
        let lines = value.components(separatedBy: .newlines)
        let regions = lines.map { TextRegion(text: $0, rect: .zero) }
        let matches = Set(SensitiveContent.candidates(in: RecognitionResult(text: regions)).map(\.label))
        return lines.map { matches.contains($0) ? "[redacted]" : $0 }.joined(separator: "\n")
    }

    func pixels(redact: Bool) throws -> CGImage {
        guard redact, !candidates.isEmpty else { return image }
        // Opaque covers match the editor's Smart redact and leave the editable document intact.
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw DocumentRenderer.Error.tooLarge }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        ctx.translateBy(x: 0, y: CGFloat(image.height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setFillColor(gray: 0, alpha: 1)
        for candidate in candidates { ctx.fill(candidate.rect.integral) }
        guard let covered = ctx.makeImage() else { throw DocumentRenderer.Error.tooLarge }
        return covered
    }

    static func pixelRect(_ rect: CGRect, in document: CaptureDocument) -> CGRect {
        let layout = DocumentRenderer.layout(document)
        return rect.offsetBy(dx: layout.content.minX - layout.crop.minX, dy: layout.content.minY - layout.crop.minY)
            .integral.intersection(CGRect(origin: .zero, size: layout.size))
    }
}
