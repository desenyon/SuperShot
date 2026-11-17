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
