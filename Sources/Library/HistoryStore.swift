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
    public init(id: UUID, date: Date, title: String, width: Int, height: Int, text: String, conversation: String? = nil) {
        self.id = id; self.date = date; self.title = title; self.width = width; self.height = height; self.text = text
        self.conversation = conversation
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
    public let folder: URL
    private var entries: [HistoryEntry] = []
    private var loaded=false
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
    private func persistIndex() throws {try JSONEncoder().encode(entries).write(to:folder.appendingPathComponent("index.json"),options:.atomic)}
    public func all(query: String = "") throws -> [HistoryEntry] {
        try load()
        let needle = searchText(query)
        return entries.filter {needle.isEmpty || searchText("\($0.title) \($0.text) \($0.conversation ?? "")").contains(needle)}.sorted{$0.date > $1.date}
    }
    private func searchText(_ text:String)->String {
        // OCR may split a word or a phrase across regions. Whitespace should
        // not prevent a user from finding text that is visibly in the image.
        text.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:.current).filter{!$0.isWhitespace}
    }
    public func save(_ document: CaptureDocument, text: String = "", retentionDays: Int = 30, onlyIfMissing: Bool = false) throws {
        try load()
        if onlyIfMissing && entries.contains(where:{$0.id == document.id}) {return}
        try ProjectFile.encode(document).write(to:projectURL(document.id),options:.atomic)
        let size=DocumentRenderer.layout(document).size
        let preview=try DocumentRenderer.render(document,scale:min(1,480/max(size.width,size.height)))
        try ImageExport.encode(preview).write(to:thumbnailURL(document.id),options:.atomic)
        let old=entries.first{$0.id == document.id}
        entries.removeAll{$0.id == document.id}
        entries.append(HistoryEntry(id:document.id,date:document.date,title:document.source,width:Int(size.width),height:Int(size.height),
                                    text:text.isEmpty ? old?.text ?? "":text,conversation:old?.conversation))
        try persistIndex()
        try prune(days:retentionDays)
    }
    public func updateText(_ text: String, id: UUID) throws {
        try load();guard let index=entries.firstIndex(where:{$0.id == id}) else{return}
        entries[index].text=text;try persistIndex()
    }
    public func document(_ id: UUID) throws -> CaptureDocument {try ProjectFile.decode(Data(contentsOf:projectURL(id)))}
    public func remove(_ id: UUID) throws {
        try load();entries.removeAll{$0.id == id};try persistIndex()
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
        let expired=entries.filter{$0.date < cutoff}.map(\.id)
        for id in expired {try remove(id)}
    }
    public nonisolated func thumbnailURL(_ id: UUID) -> URL {folder.appendingPathComponent(id.uuidString+".png")}
    private nonisolated func conversationURL(_ id: UUID) -> URL {folder.appendingPathComponent(id.uuidString+".ask.json")}
    private nonisolated func projectURL(_ id: UUID) -> URL {folder.appendingPathComponent(id.uuidString+".supershot")}
}
