import Foundation

/// User-entered information belongs to the capture in Library and stays on this Mac.
public struct HistoryMetadata: Codable, Equatable, Sendable {
    public var title: String
    /// A nil value follows the generated tags. An empty list explicitly clears them.
    public var tags: [String]?
    public var notes: String
    public var collection: String
    public var reminder: Date?
    public var summary: String

    public init(title: String = "", tags: [String]? = nil, notes: String = "",
                collection: String = "", reminder: Date? = nil, summary: String = "") {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tags = tags.map(cleanHistoryTags)
        self.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        self.collection = collection.trimmingCharacters(in: .whitespacesAndNewlines)
        self.reminder = reminder
        self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Machine-generated metadata is stored independently so a late model reply cannot overwrite an edit.
public struct HistorySuggestions: Codable, Equatable, Sendable {
    public let title: String?
    public let tags: [String]
    public let summary: String?

    public init(title: String? = nil, tags: [String] = [], summary: String? = nil) {
        self.title = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tags = cleanHistoryTags(tags)
        self.summary = summary?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private func cleanHistoryTags(_ tags: [String]) -> [String] {
    var seen: Set<String> = []
    return tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { tag in
        !tag.isEmpty && seen.insert(tag.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)).inserted
    }
}
