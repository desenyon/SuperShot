import Testing
import Foundation
import CoreGraphics
import Document
import Export
@testable import Library

struct HistoryTests {
    func document() throws -> CaptureDocument {
        let c=CGContext(data:nil,width:40,height:30,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(CGColor(gray:1,alpha:1));c.fill(CGRect(x:0,y:0,width:40,height:30))
        return CaptureDocument(original:try ImageExport.encode(c.makeImage()!),width:40,height:30,source:"Test Capture")
    }
    @Test func historySurvivesRestartSearchesOCRAndRetainsEdits() async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:folder)}
        let store=HistoryStore(folder:folder);let original=try document()
        try await store.save(original)
        try await store.updateText("invoice number 1234",id:original.id)
        var edited=original;edited.layers=[Layer(kind:.rectangle,rect:CGRect(x:2,y:2,width:10,height:10))]
        try await store.save(edited)
        try await store.save(original,onlyIfMissing:true)
        let reopened=HistoryStore(folder:folder)
        #expect(try await reopened.all(query:"invoice").count == 1)
        #expect(try await reopened.document(original.id).layers.count == 1)
        try await reopened.remove(original.id)
        #expect(try await reopened.all().isEmpty)
    }
    @Test func corruptIndexRecoversProjectsAndPreservesBackup() async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:folder)}
        let original=try document();try await HistoryStore(folder:folder).save(original)
        try Data("broken".utf8).write(to:folder.appendingPathComponent("index.json"))
        let recovered=try await HistoryStore(folder:folder).all()
        #expect(recovered.count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath:folder.path).contains{$0.hasPrefix("index-recovery-")})
    }
    @Test func lateEditorAutosaveCannotRestoreAnOlderVersion() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = HistoryStore(folder: folder)
        let old = try document()
        var edited = old
        edited.crop = CGRect(x: 0, y: 0, width: 20, height: 20)
        #expect(try await store.storedDocument(old.id) == nil)
        try await store.save(edited, revision: 2)
        try await store.save(old, revision: 1)
        #expect(try await store.storedDocument(old.id) == edited)
    }
    @Test func searchToleratesOCRWordSplitsAndLineBreaks() async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:folder)}
        let store=HistoryStore(folder:folder), capture=try document()
        try await store.save(capture,text:"Ref erence\n55534\nCafé notes")
        #expect(try await store.all(query:"Reference 55534").count == 1)
        #expect(try await store.all(query:"cafe notes").count == 1)
        #expect(try await store.all(query:"Reference 123").isEmpty)
    }
}

struct ConversationHistoryTests {
    @Test func conversationsAreKeptSearchableAndRemovedWithTheirCapture() async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:folder)}
        let store=HistoryStore(folder:folder), capture=try HistoryTests().document()
        // Not in History yet: nothing is written.
        try await store.saveConversation([StoredMessage(role:"user",text:"Ignored")],id:capture.id)
        #expect(try await store.conversation(capture.id).isEmpty)
        try await store.save(capture)
        let messages=[StoredMessage(role:"user",text:"What is the renewal error?",attachments:["Region 1 · 20 × 10"]),
                      StoredMessage(role:"assistant",text:"The card verification failed.")]
        try await store.saveConversation(messages,id:capture.id)
        #expect(try await store.conversation(capture.id) == messages)
        #expect(try await HistoryStore(folder:folder).all(query:"card verification").map(\.id) == [capture.id])
        let file=folder.appendingPathComponent(capture.id.uuidString+".ask.json")
        let mode=try FileManager.default.attributesOfItem(atPath:file.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
        // Re-saving the capture keeps its conversation.
        try await store.save(capture)
        #expect(try await store.all(query:"renewal").count == 1)
        try await store.remove(capture.id)
        #expect(!FileManager.default.fileExists(atPath:file.path))
    }
    @Test func turningTheSettingOffForgetsEveryConversation() async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:folder)}
        let store=HistoryStore(folder:folder), capture=try HistoryTests().document()
        try await store.save(capture)
        try await store.saveConversation([StoredMessage(role:"assistant",text:"Kept reply")],id:capture.id)
        try await store.removeAllConversations()
        #expect(try await store.conversation(capture.id).isEmpty)
        #expect(try await store.all(query:"Kept reply").isEmpty)
        #expect(try await store.all().count == 1)
    }
}
