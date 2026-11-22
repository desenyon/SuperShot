import Testing
import Foundation
@testable import Library

struct HistoryMetadataTests {
    @Test func organizesAndSearchesEditedCapturesAfterRestart() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = HistoryStore(folder: folder)
        let capture = try HistoryTests().document()
        let reminder = Date(timeIntervalSinceReferenceDate: 813_100_000)
        try await store.save(capture, text: "Ref erence\n321")
        try await store.updateSuggestions(
            HistorySuggestions(title: "Generated screenshot", tags: ["Design"], summary: "A white test image"),
            id: capture.id
        )
        try await store.updateMetadata(
            HistoryMetadata(title: "  QA dashboard ", tags: [" Café ", "CAFE", " "], notes: "Verify billing",
                            collection: " Release ", reminder: reminder, summary: "Manual summary"),
            id: capture.id
        )
        try await store.save(capture)
        let reopened = HistoryStore(folder: folder)
        let entry = try #require(await reopened.all().first)
        #expect(entry.displayTitle == "QA dashboard")
        #expect(entry.displayTags == ["Café"])
        #expect(entry.displaySummary == "Manual summary")
        #expect(entry.metadata?.reminder == reminder)
        #expect(entry.metadata?.collection == "Release")
        for query in ["dashboard", "cafe", "verify billing", "release", "manual summary", "Reference 321"] {
            #expect(try await reopened.all(query: query).map(\.id) == [capture.id])
        }
    }

    @Test func editsWinOverSuggestionsAndLateWorkCannotRecreateDeletedEntries() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = HistoryStore(folder: folder)
        let capture = try HistoryTests().document()
        try await store.save(capture)
        try await store.updateMetadata(HistoryMetadata(title: "Manual", tags: []), id: capture.id)
        let suggestions = HistorySuggestions(title: "Background", tags: ["Generated"], summary: "Generated summary")
        try await store.updateSuggestions(suggestions, id: capture.id)
        let entry = try #require(await store.all().first)
        #expect(entry.displayTitle == "Manual")
        #expect(entry.displayTags.isEmpty)
        #expect(entry.displaySummary == "Generated summary")
        try await store.remove(capture.id)
        try await store.updateSuggestions(suggestions, id: capture.id)
        try await store.updateMetadata(HistoryMetadata(title: "Deleted"), id: capture.id)
        try await store.save(capture)
        #expect(try await HistoryStore(folder: folder).all().isEmpty)
    }

    @Test func missingMetadataDecodesFromOlderIndex() throws {
        let id = UUID()
        let payload = Data("""
        {"id":"\(id.uuidString)","date":0,"title":"Safari","width":32,"height":24,"text":"recognized"}
        """.utf8)
        let entry = try JSONDecoder().decode(HistoryEntry.self, from: payload)
        #expect(entry.id == id)
        #expect(entry.displayTitle == "Safari")
        #expect(entry.displayTags.isEmpty)
        #expect(entry.metadata == nil)
        #expect(entry.suggestions == nil)
    }

    @Test func remindersAreRetainedUntilCleared() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = HistoryStore(folder: folder)
        var capture = try HistoryTests().document()
        capture.date = Date(timeIntervalSinceReferenceDate: 100)
        try await store.save(capture, retentionDays: 0)
        try await store.updateMetadata(HistoryMetadata(collection: "Design", reminder: .now), id: capture.id)
        try await store.prune(days: 1)
        #expect(try await store.collectionNames() == ["Design"])
        #expect(try await store.all().map(\.id) == [capture.id])
        try await store.updateMetadata(HistoryMetadata(collection: "Design"), id: capture.id)
        try await store.prune(days: 1)
        #expect(try await store.all().isEmpty)
    }
}
