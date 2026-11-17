import Foundation
import CoreGraphics
import Vision

public struct TextRegion: Codable, Identifiable, Sendable {
    public var id: UUID
    public var text: String
    public var rect: CGRect
    public var confidence: Float
    public init(id: UUID = UUID(), text: String, rect: CGRect, confidence: Float = 1) { self.id=id;self.text=text;self.rect=rect;self.confidence=confidence }
}
public struct CodeRegion: Codable, Identifiable, Sendable {
    public var id: UUID
    public var payload: String
    public var rect: CGRect
    public init(id: UUID = UUID(), payload: String, rect: CGRect) {self.id=id;self.payload=payload;self.rect=rect}
}
public struct RecognitionResult: Codable, Sendable {
    public var text: [TextRegion]
    public var codes: [CodeRegion]
    public var faces: [CGRect]
    public var transcript: String { text.map(\.text).joined(separator:"\n") }
    public init(text: [TextRegion] = [], codes: [CodeRegion] = [], faces: [CGRect] = []) {self.text=text;self.codes=codes;self.faces=faces}
}
public actor RecognitionService {
    public init() {}
    public func recognize(_ image: CGImage, accurate: Bool = false) async throws -> RecognitionResult {
        let size=CGSize(width:image.width,height:image.height)
        var request=RecognizeTextRequest();request.recognitionLevel=accurate ? .accurate:.fast;request.automaticallyDetectsLanguage=true
        // Vision defaults to 1/32 of image height: 90 px on a 5K display,
        // which silently excludes ordinary UI text in its fast path.
        request.minimumTextHeightFraction = Float(min(1, 8.0 / Double(max(1, image.height))))
        async let text=request.perform(on:image)
        async let codes=DetectBarcodesRequest().perform(on:image)
        async let faces=DetectFaceRectanglesRequest().perform(on:image)
        return try await RecognitionResult(
            text:text.map {TextRegion(text:$0.transcript,rect:$0.boundingBox.toImageCoordinates(size,origin:.upperLeft),confidence:$0.confidence)},
            codes:codes.compactMap {code in code.payloadString.map{CodeRegion(payload:$0,rect:code.boundingBox.toImageCoordinates(size,origin:.upperLeft))}},
            faces:faces.map{$0.boundingBox.toImageCoordinates(size,origin:.upperLeft)}
        )
    }
}

public struct RedactionCandidate: Identifiable, Sendable {
    public let id: UUID
    public let label: String
    public let rect: CGRect
    public init(label: String, rect: CGRect) {id=UUID();self.label=label;self.rect=rect}
}
public enum SensitiveContent {
    public static func candidates(in result: RecognitionResult) -> [RedactionCandidate] {
        let detector=try? NSDataDetector(types:NSTextCheckingResult.CheckingType.link.rawValue | NSTextCheckingResult.CheckingType.phoneNumber.rawValue | NSTextCheckingResult.CheckingType.address.rawValue)
        let patterns=[#"\b(?:sk|pk|api|token|secret)[-_][A-Za-z0-9_-]{12,}\b"#,#"\b(?:\d[ -]*?){13,19}\b"#,#"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#]
        let regex=patterns.compactMap{try? NSRegularExpression(pattern:$0,options:.caseInsensitive)}
        var output=result.text.compactMap {region -> RedactionCandidate? in
            let range=NSRange(region.text.startIndex...,in:region.text)
            let sensitive=regex.contains{$0.firstMatch(in:region.text,range:range) != nil} || (detector?.matches(in:region.text,range:range).contains {match in
                match.resultType == .phoneNumber || match.resultType == .address || match.url?.scheme == "mailto"
            } ?? false)
            return sensitive ? RedactionCandidate(label:region.text,rect:region.rect.insetBy(dx:-4,dy:-4)):nil
        }
        output += result.faces.map{RedactionCandidate(label:"Face",rect:$0.insetBy(dx:-6,dy:-6))}
        return output
    }
}
