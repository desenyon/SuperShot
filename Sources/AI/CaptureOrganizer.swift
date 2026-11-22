import CoreGraphics
import Foundation
import Recognition
import Vision

public actor CaptureOrganizer {
    public struct Suggestion: Sendable, Equatable {
        public var title: String?
        public var tags: [String]
        public var summary: String?
    }

    private let model = LocalAIProvider()
    public init() {}

    public func suggest(image: CGImage, recognition: RecognitionResult, source: String, useAppleIntelligence: Bool = true) async -> Suggestion {
        let classifications = try? await ImageRequestHandler(image).perform(ClassifyImageRequest())
        let labels = classifications?.filter { $0.confidence >= 0.35 }.prefix(4).map(\.identifier) ?? []
        var suggestion = Self.suggestion(from: recognition.transcript, source: source, labels: labels)
        if useAppleIntelligence {
            if case let .text(title)? = try? await model.perform(.filename, image: image, recognition: recognition),
               let title = Self.nonempty(title, limit: 80) {
                suggestion.title = title
            }
            if case let .text(summary)? = try? await model.perform(.describe, image: image, recognition: recognition),
               let summary = Self.nonempty(summary, limit: 360) {
                suggestion.summary = summary
            }
        }
        return suggestion
    }

    static func suggestion(from transcript: String, source: String, labels: [String]) -> Suggestion {
        let lines = transcript.split(whereSeparator: \.isNewline)
            .compactMap { nonempty(String($0), limit: 140) }
        let title = lines.first(where: { $0.count > 8 }).flatMap { nonempty($0, limit: 80) }
        var seen = Set<String>()
        let tags = ([source] + labels.map { $0.replacingOccurrences(of: "_", with: " ") })
            .compactMap { nonempty($0, limit: 28) }
            .filter { seen.insert($0.lowercased()).inserted }
        let summary = nonempty(lines.prefix(3).joined(separator: " · "), limit: 360)
        return Suggestion(title: title, tags: Array(tags.prefix(5)), summary: summary)
    }

    private static func nonempty(_ value: String, limit: Int) -> String? {
        let text = String(value.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(limit))
        return text.isEmpty ? nil : text
    }
}
