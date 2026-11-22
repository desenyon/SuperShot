import Document
import Foundation
import Testing
@testable import Library

struct LinkedExportTests {
    @Test func linkedExportSurvivesRelaunchAndAppliesNewestEdit() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = try HistoryTests().document()
        let path = folder.appendingPathComponent("capture.png")
        try original.original.write(to: path)
        let format = LinkedExports.Format(type: "public.png", scaleFactor: 1, sRGB: true, quality: 1)
        try await LinkedExports(folder: folder).link(id: original.id, url: path, bytes: original.original, format: format)

        let restarted = LinkedExports(folder: folder)
        var edited = original
        edited.layers = [Layer(kind: .rectangle, rect: CGRect(x: 3, y: 3, width: 25, height: 19), color: .black, filled: true)]
        #expect(try await restarted.refresh(edited, revision: 2) == .updated)
        let bytes = try Data(contentsOf: path)
        #expect(bytes != original.original)
        #expect(try await restarted.refresh(original, revision: 1) == .unchanged)
        #expect(try Data(contentsOf: path) == bytes)
        #expect(try await LinkedExports(folder: folder).refresh(edited, revision: 1) == .unchanged)
    }

    @Test func changedFileDetachesAndIsNeverRecreated() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let capture = try HistoryTests().document()
        let path = folder.appendingPathComponent("capture.png")
        try capture.original.write(to: path)
        let store = LinkedExports(folder: folder)
        let format = LinkedExports.Format(type: "public.png", scaleFactor: 1, sRGB: true, quality: 1)
        try await store.link(id: capture.id, url: path, bytes: capture.original, format: format)
        let replacement = Data(repeating: 42, count: capture.original.count)
        try replacement.write(to: path, options: .atomic)
        #expect(try await store.refresh(capture, revision: 1) == .detached)
        #expect(try Data(contentsOf: path) == replacement)
        try FileManager.default.removeItem(at: path)
        #expect(try await LinkedExports(folder: folder).refresh(capture, revision: 1) == .unchanged)
        #expect(!FileManager.default.fileExists(atPath: path.path))
    }
}
