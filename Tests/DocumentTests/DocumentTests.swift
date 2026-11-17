import Testing
import Foundation
import CoreGraphics
@testable import Document

struct DocumentTests {
    @Test func undoPreservesOriginalAndBranches() throws {
        let original = Data([1, 2, 3])
        var history = DocumentHistory(document: CaptureDocument(original: original, width: 800, height: 600))
        history.change { $0.layers.append(Layer(kind: .rectangle, rect: CGRect(x: 10, y: 20, width: 40, height: 30))) }
        history.change { $0.crop = CGRect(x: 10, y: 10, width: 300, height: 200) }
        history.undo()
        #expect(history.document.crop == nil)
        #expect(history.document.layers.count == 1)
        history.redo()
        #expect(history.document.crop?.width == 300)
        history.undo()
        history.change { $0.layers.removeAll() }
        #expect(!history.canRedo)
        #expect(history.document.original == original)
    }
    @Test func projectRoundTripRetainsEditableLayers() throws {
        var document = CaptureDocument(original: Data([1, 2, 3]), width: 800, height: 600)
        document.layers = [Layer(kind: .text, rect: CGRect(x: 20, y: 40, width: 100, height: 30), text: "Hello, 世界")]
        document.backdrop.padding = 48
        let restored = try ProjectFile.decode(ProjectFile.encode(document))
        #expect(restored == document)
    }
    @Test func rejectsFutureProjectVersion() throws {
        let data = Data("{\"version\":999}".utf8)
        #expect(throws: ProjectFile.Error.self) { try ProjectFile.decode(data) }
    }
}

extension DocumentTests {
    @Test func rejectsSubnormalScaleAndExplosiveAspectRatio() throws {
        var doc=CaptureDocument(original:Data([1]),width:800,height:600)
        doc.scale=1e-300
        #expect(throws:ProjectFile.Error.self){try ProjectFile.decode(ProjectFile.encode(doc))}
        doc.scale=1;doc.backdrop.fill = .solid;doc.backdrop.ratio=1e-300
        #expect(throws:ProjectFile.Error.self){try ProjectFile.decode(ProjectFile.encode(doc))}
    }
}
