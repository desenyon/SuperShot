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
    public init(id: UUID, date: Date, title: String, width: Int, height: Int, text: String) {
        self.id = id; self.date = date; self.title = title; self.width = width; self.height = height; self.text = text
    }
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
        return entries.filter {needle.isEmpty || searchText("\($0.title) \($0.text)").contains(needle)}.sorted{$0.date > $1.date}
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
        let oldText=entries.first{$0.id == document.id}?.text ?? ""
        entries.removeAll{$0.id == document.id}
        entries.append(HistoryEntry(id:document.id,date:document.date,title:document.source,width:Int(size.width),height:Int(size.height),text:text.isEmpty ? oldText:text))
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
        for url in [projectURL(id),thumbnailURL(id)] where FileManager.default.fileExists(atPath:url.path) {try FileManager.default.removeItem(at:url)}
    }
    public func prune(days: Int) throws {
        guard days > 0 else{return}
        let cutoff=Date().addingTimeInterval(-Double(days)*86400)
        let expired=entries.filter{$0.date < cutoff}.map(\.id)
        for id in expired {try remove(id)}
    }
    public nonisolated func thumbnailURL(_ id: UUID) -> URL {folder.appendingPathComponent(id.uuidString+".png")}
    private nonisolated func projectURL(_ id: UUID) -> URL {folder.appendingPathComponent(id.uuidString+".supershot")}
}
