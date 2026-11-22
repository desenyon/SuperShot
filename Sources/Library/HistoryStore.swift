import Foundation
import CoreGraphics
import ImageIO
import Document
import Render
import Export

public struct HistoryEntry: Codable, Identifiable, Sendable {
    public var id: UUID
    public var date: Date
    public var title: String
    public var width: Int
    public var height: Int
    public var text: String
    /// Plain text of the saved Ask conversation, for search. Absent in older indexes.
    public var conversation: String?
    public var metadata: HistoryMetadata?
    public var suggestions: HistorySuggestions?
    public var updatedAt: Date?

    public var displayTitle: String {
        [metadata?.title, suggestions?.title, title].compactMap { $0 }.first { !$0.isEmpty } ?? "Screenshot"
    }
    public var displayTags: [String] { metadata?.tags ?? suggestions?.tags ?? [] }
    public var displaySummary: String? {
        [metadata?.summary, suggestions?.summary].compactMap { $0 }.first { !$0.isEmpty }
    }

    public init(id: UUID, date: Date, title: String, width: Int, height: Int, text: String, conversation: String? = nil,
                metadata: HistoryMetadata? = nil, suggestions: HistorySuggestions? = nil, updatedAt: Date? = nil) {
        self.id = id; self.date = date; self.title = title; self.width = width; self.height = height; self.text = text
        self.conversation = conversation
        self.metadata = metadata
        self.suggestions = suggestions
        self.updatedAt = updatedAt
    }
}

/// One message of an Ask conversation kept with its capture.
public struct StoredMessage: Codable, Equatable, Sendable {
    public var role: String
    public var text: String
    public var attachments: [String]
    public init(role: String, text: String, attachments: [String] = []) { self.role = role; self.text = text; self.attachments = attachments }
}
public actor HistoryStore {
    public nonisolated let folder: URL
    private var entries: [HistoryEntry] = []
    private var loaded=false
    private var latestRevisions: [UUID: UInt64] = [:]
    // Open editors may still have a pending autosave when an item is deleted or pruned.
    private var removedInSession: Set<UUID> = []
    public init(folder: URL? = nil) {
        self.folder=folder ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("SuperShot/History",isDirectory:true)
    }
    private func load() throws {
        guard !loaded else {return}
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let index=folder.appendingPathComponent("index.json")
        if FileManager.default.fileExists(atPath:index.path) {
            do {entries=try JSONDecoder().decode([HistoryEntry].self,from:Data(contentsOf:index))}
            catch {
                // Preserve a damaged index, then recover metadata from intact project files.
                try? FileManager.default.copyItem(at:index,to:folder.appendingPathComponent("index-recovery-\(UUID().uuidString).json"))
                entries=[]
                for url in try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil) where url.pathExtension == "supershot" {
                    if let data=try? Data(contentsOf:url),let doc=try? ProjectFile.decode(data) {
                        entries.append(HistoryEntry(id:doc.id,date:doc.date,title:doc.source,width:doc.width,height:doc.height,text:""))
                    }
                }
            }
        }
        loaded=true
    }
    private func persistIndex() throws { try writeIndex(entries) }
    private func writeIndex(_ updated: [HistoryEntry]) throws {
        try JSONEncoder().encode(updated).write(to: folder.appendingPathComponent("index.json"), options: .atomic)
    }
    public func all(query: String = "") throws -> [HistoryEntry] {
        try load()
        let needle = searchText(query)
        return entries.filter { entry in
            guard !needle.isEmpty else { return true }
            let originalSearch = "\(entry.title) \(entry.text) \(entry.conversation ?? "")"
            let fields = [originalSearch, entry.displayTitle, entry.metadata?.collection ?? "", entry.metadata?.notes ?? "",
                          entry.displaySummary ?? ""] + entry.displayTags
            return fields.contains { searchText($0).contains(needle) }
        }.sorted { left, right in
            left.date == right.date ? left.id.uuidString < right.id.uuidString : left.date > right.date
        }
    }
    public func collectionNames() throws -> [String] {
        try load()
        let names = entries.compactMap { $0.metadata?.collection }.filter { !$0.isEmpty }
        var seen: Set<String> = []
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.filter {
            seen.insert($0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)).inserted
        }
    }
    private func searchText(_ text:String)->String {
        // OCR may split a word or a phrase across regions. Whitespace should
        // not prevent a user from finding text that is visibly in the image.
        text.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:.current).filter{!$0.isWhitespace}
    }
    public func save(_ document: CaptureDocument, text: String = "", retentionDays: Int = 30,
                     onlyIfMissing: Bool = false, revision: UInt64? = nil) throws {
        try load()
        guard !removedInSession.contains(document.id) else { return }
        if onlyIfMissing && entries.contains(where:{$0.id == document.id}) {return}
        if let revision, revision <= (latestRevisions[document.id] ?? 0) { return }
        let data = try ProjectFile.encode(document)
        let size=DocumentRenderer.layout(document).size
        let preview=try DocumentRenderer.render(document,scale:min(1,480/max(size.width,size.height)))
        let thumbnail = try ImageExport.encode(preview)
        try data.write(to: projectURL(document.id), options: .atomic)
        try thumbnail.write(to: thumbnailURL(document.id), options: .atomic)
        let old=entries.first{$0.id == document.id}
        var updated = entries.filter { $0.id != document.id }
        updated.append(HistoryEntry(id: document.id, date: document.date, title: document.source,
                                    width: Int(size.width), height: Int(size.height),
                                    text: text.isEmpty ? old?.text ?? "" : text, conversation: old?.conversation,
                                    metadata: old?.metadata, suggestions: old?.suggestions, updatedAt: .now))
        try writeIndex(updated)
        entries = updated
        if let revision { latestRevisions[document.id] = revision }
        try prune(days:retentionDays)
    }
    @discardableResult public func updateMetadata(_ metadata: HistoryMetadata, id: UUID) throws -> HistoryEntry? {
        try updateEntry(id) {
            $0.metadata = HistoryMetadata(title: metadata.title, tags: metadata.tags, notes: metadata.notes,
                                          collection: metadata.collection, reminder: metadata.reminder,
                                          summary: metadata.summary)
        }
    }
    @discardableResult public func updateSuggestions(_ suggestions: HistorySuggestions, id: UUID) throws -> HistoryEntry? {
        try updateEntry(id) { $0.suggestions = suggestions }
    }
    private func updateEntry(_ id: UUID, change: (inout HistoryEntry) -> Void) throws -> HistoryEntry? {
        try load()
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return nil }
        var updated = entries
        change(&updated[index])
        try writeIndex(updated)
        entries = updated
        return updated[index]
    }
    public func updateText(_ text: String, id: UUID) throws {
        _ = try updateEntry(id) { $0.text = text }
    }
    public func document(_ id: UUID) throws -> CaptureDocument {try ProjectFile.decode(Data(contentsOf:projectURL(id)))}
    public func storedDocument(_ id: UUID) throws -> CaptureDocument? {
        do { return try document(id) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
    }
    public func wasRemoved(_ id: UUID) -> Bool { removedInSession.contains(id) }
    public func remove(_ id: UUID) throws {
        try load()
        let updated = entries.filter { $0.id != id }
        try writeIndex(updated)
        entries = updated
        removedInSession.insert(id)
        latestRevisions.removeValue(forKey: id)
        for url in [projectURL(id),thumbnailURL(id),conversationURL(id)] where FileManager.default.fileExists(atPath:url.path) {try FileManager.default.removeItem(at:url)}
    }
    /// Keeps an Ask conversation with its capture. An empty list removes it.
    /// Only captures already in History keep conversations, so retention and deletion cover them too.
    public func saveConversation(_ messages: [StoredMessage], id: UUID) throws {
        try load()
        guard let index=entries.firstIndex(where:{$0.id == id}) else {return}
        let url=conversationURL(id)
        if messages.isEmpty {
            if FileManager.default.fileExists(atPath:url.path) {try FileManager.default.removeItem(at:url)}
            entries[index].conversation=nil
        } else {
            try JSONEncoder().encode(messages).write(to:url,options:[.atomic])
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
            entries[index].conversation=messages.map(\.text).joined(separator:"\n")
        }
        try persistIndex()
    }
    public func conversation(_ id: UUID) throws -> [StoredMessage] {
        let url=conversationURL(id)
        guard FileManager.default.fileExists(atPath:url.path) else {return []}
        return try JSONDecoder().decode([StoredMessage].self,from:Data(contentsOf:url))
    }
    /// Deletes every kept conversation, for when the user turns the setting off.
    public func removeAllConversations() throws {
        try load()
        for index in entries.indices {
            let url=conversationURL(entries[index].id)
            if FileManager.default.fileExists(atPath:url.path) {try FileManager.default.removeItem(at:url)}
            entries[index].conversation=nil
        }
        try persistIndex()
    }
    public func prune(days: Int) throws {
        guard days > 0 else{return}
        let cutoff=Date().addingTimeInterval(-Double(days)*86400)
        let expired = entries.filter { $0.date < cutoff && $0.metadata?.reminder == nil }.map(\.id)
        for id in expired {try remove(id)}
    }
    public nonisolated func thumbnailURL(_ id: UUID) -> URL {folder.appendingPathComponent(id.uuidString+".png")}
    private nonisolated func conversationURL(_ id: UUID) -> URL {folder.appendingPathComponent(id.uuidString+".ask.json")}
    private nonisolated func projectURL(_ id: UUID) -> URL {folder.appendingPathComponent(id.uuidString+".supershot")}
}
