import Testing
import AppKit
import Foundation
import Document
import Recognition
import Export
import CoreGraphics
@testable import Editor

struct EditorTests {
    @Test @MainActor func narrowEditorFitsImageBesideOnlyTheActiveInspector() async {
        let model = EditorModel(document: CaptureDocument(original: Data(), width: 1400, height: 900))
        model.inspector = "layers"
        let canvas = CanvasView(model: model)
        canvas.frame = CGRect(x: 0, y: 0, width: 980, height: 620)
        canvas.sync()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(model.displayScale > 0.4)
    }

    @Test @MainActor func restoringAnInspectorKeepsTheChosenZoom() {
        let model = EditorModel(document: CaptureDocument(original: Data(), width: 1400, height: 900))
        model.setZoom(1.25)
        model.inspector = "layers"
        #expect(model.visiblePanels(width: 980).inspector == "layers")
        #expect(!model.visiblePanels(width: 980).backdrop)
        model.showBackdrop = true
        #expect(model.visiblePanels(width: 980).inspector.isEmpty)
        #expect(model.visiblePanels(width: 980).backdrop)
        #expect(model.visiblePanels(width: 1280).inspector == "layers")
        #expect(model.visiblePanels(width: 1280).backdrop)
        #expect(model.zoom == 1.25)
    }

    @Test @MainActor func exportDimensionsIncludeCropBackdropAndOutputScale() {
        var document = CaptureDocument(original: Data(), width: 1400, height: 900)
        document.crop = CGRect(x: 10, y: 10, width: 701, height: 301)
        document.backdrop.fill = .solid
        document.backdrop.padding = 12
        let model = EditorModel(document: document)
        model.fileExportScale = { 0.5 }
        #expect(model.exportDimensions(at: 1) == CGSize(width: 363, height: 163))
        #expect(model.exportDimensions(at: 2) == CGSize(width: 725, height: 325))
    }

    @Test @MainActor func gestureCommitsOnceAndUndoRemovesWholeStroke() {
        let model = EditorModel(document: CaptureDocument(original: Data(), width: 800, height: 600))
        let tool = DrawingTool()
        let layer = tool.makeLayer(start: .zero, end: CGPoint(x: 90, y: 70), points: [.zero, CGPoint(x: 20, y: 30), CGPoint(x: 90, y: 70)], style: ToolStyle())
        model.commit { $0.layers.append(layer) }
        #expect(model.document.layers.count == 1)
        model.undo()
        #expect(model.document.layers.isEmpty)
        model.redo()
        #expect(model.document.layers.first?.points.count == 3)
    }
    @Test @MainActor func selectionDeleteCanBeUndone() {
        var doc = CaptureDocument(original: Data(), width: 800, height: 600)
        let layer = Layer(kind: .arrow, rect: CGRect(x: 20, y: 30, width: 90, height: 80))
        doc.layers = [layer]
        let model = EditorModel(document: doc)
        model.selected = [layer.id]
        model.deleteSelection()
        #expect(model.document.layers.isEmpty)
        model.undo()
        #expect(model.document.layers.first?.id == layer.id)
    }
}

extension EditorTests {
    @Test @MainActor func editingInvalidatesRedactionProposals() {
        let model=EditorModel(document:CaptureDocument(original:Data(),width:800,height:600))
        let candidate=Recognition.RedactionCandidate(label:"Sensitive text",rect:CGRect(x:20,y:20,width:100,height:30))
        model.redactions=[candidate];model.acceptedRedactions=[candidate.id]
        model.generatedText="Outdated description";model.status="Text recognized on your Mac"
        model.commit{$0.layers.append(Layer(kind:.rectangle,rect:CGRect(x:20,y:100,width:100,height:30)))}
        #expect(model.redactions.isEmpty && model.acceptedRedactions.isEmpty)
        #expect(model.generatedText.isEmpty && model.status.isEmpty)
    }
    @Test @MainActor func explicitFlushSavesLatestEditBeforeDebounce() {
        let model=EditorModel(document:CaptureDocument(original:Data(),width:800,height:600))
        var saved:CaptureDocument?
        model.autosaveAction={saved=$0}
        model.commit{$0.layers.append(Layer(kind:.text,rect:CGRect(x:10,y:10,width:100,height:40),text:"Keep me"))}
        model.flushAutosave()
        #expect(saved?.layers.first?.text == "Keep me")
    }
}

extension EditorTests {
    @Test @MainActor func zoomAtOneHundredPercentRendersEverySourcePixel() async throws {
        let context=CoreGraphics.CGContext(data:nil,width:3000,height:30,bitsPerComponent:8,bytesPerRow:0,space:CoreGraphics.CGColorSpaceCreateDeviceRGB(),bitmapInfo:CoreGraphics.CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image=context.makeImage()!,data=try Export.ImageExport.encode(image)
        let model=EditorModel(document:CaptureDocument(original:data,width:3000,height:30))
        for _ in 0..<100 {if model.image?.width == 2200 {break};try await Task.sleep(for:.milliseconds(10))}
        #expect(model.image?.width == 2200)
        model.zoom=1
        for _ in 0..<100 {if model.image?.width == 3000 {break};try await Task.sleep(for:.milliseconds(10))}
        #expect(model.image?.width == 3000)
    }
}

extension EditorTests {
    @Test @MainActor func sliderDragPreviewsLiveAndRecordsOneUndoStep() {
        let model = EditorModel(document: CaptureDocument(original: Data(), width: 800, height: 600))
        for padding in [10.0, 40, 90, 120] { model.previewChange { $0.backdrop.padding = padding } }
        #expect(model.current.backdrop.padding == 120)
        #expect(!model.canUndo)
        model.commitDraft()
        #expect(model.document.backdrop.padding == 120)
        model.undo()
        #expect(model.document.backdrop.padding == 64 && !model.canUndo)
    }
    @Test @MainActor func restyleUpdatesTheToolAndTheSelection() {
        var doc = CaptureDocument(original: Data(), width: 800, height: 600)
        let layer = Layer(kind: .arrow, rect: CGRect(x: 20, y: 30, width: 90, height: 80))
        doc.layers = [layer]
        let model = EditorModel(document: doc)
        model.selected = [layer.id]
        model.restyle({ $0.stroke = 11 }, layers: { $0.stroke = 11 })
        #expect(model.style.stroke == 11 && model.document.layers.first?.stroke == 11)
    }
}

extension EditorTests {
    private static func solid(_ width: Int, _ height: Int) throws -> Data {
        let context = CoreGraphics.CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CoreGraphics.CGColorSpaceCreateDeviceRGB(), bitmapInfo: CoreGraphics.CGImageAlphaInfo.premultipliedLast.rawValue)!
        return try Export.ImageExport.encode(context.makeImage()!)
    }
    @MainActor private func settle(_ condition: () -> Bool) async throws {
        for _ in 0..<200 { if condition() { return }; try await Task.sleep(for: .milliseconds(10)) }
    }
    @Test @MainActor func selectedLayersLeaveTheRasterAndMoveWithoutRerendering() async throws {
        var doc = CaptureDocument(original: try Self.solid(400, 300), width: 400, height: 300)
        let arrow = Layer(kind: .arrow, rect: CGRect(x: 20, y: 30, width: 90, height: 80), points: [CGPoint(x: 20, y: 30), CGPoint(x: 110, y: 110)])
        let blur = Layer(kind: .blur, rect: CGRect(x: 200, y: 100, width: 80, height: 60))
        doc.layers = [arrow, blur]
        let model = EditorModel(document: doc)
        model.selected = [arrow.id, blur.id]
        try await settle { model.rasterExcluded == [arrow.id] }
        // The arrow is painted by the canvas; the blur samples pixels, so it stays in the raster.
        #expect(model.rasterExcluded == [arrow.id])
        let raster = try #require(model.image)
        var moved = model.document
        moved.layers[0].translate(x: 40, y: 10)
        model.preview(moved)
        try await Task.sleep(for: .milliseconds(80))
        #expect(model.image === raster)
        #expect(model.current.layers[0].rect.minX == 60)
    }
    @Test @MainActor func aContinuousDragKeepsProducingFrames() async throws {
        let model = EditorModel(document: CaptureDocument(original: try Self.solid(400, 300), width: 400, height: 300))
        model.commit { $0.backdrop.fill = .solid; $0.backdrop.padding = 0 }
        try await settle { model.image?.width == 400 }
        var widths = Set<Int>()
        for padding in stride(from: 10.0, through: 200, by: 10) {
            model.previewChange { $0.backdrop.padding = padding }
            try await Task.sleep(for: .milliseconds(12))
            if let width = model.image?.width { widths.insert(width) }
        }
        // Frames arrive during the drag, not only after it ends.
        #expect(widths.count >= 3)
        model.commitDraft()
        try await settle { model.image?.width == 800 }
        #expect(model.image?.width == 800 && model.document.backdrop.padding == 200)
    }
    @Test @MainActor func duplicateOffsetsAndSelectsTheCopy() {
        var doc = CaptureDocument(original: Data(), width: 800, height: 600)
        let layer = Layer(kind: .rectangle, rect: CGRect(x: 20, y: 30, width: 90, height: 80))
        doc.layers = [layer]
        let model = EditorModel(document: doc)
        model.selected = [layer.id]
        model.duplicateSelection()
        #expect(model.document.layers.count == 2 && model.document.layers[1].rect.minX == 44)
        #expect(model.selected == [model.document.layers[1].id])
    }
}

extension EditorTests {
    @Test func customPalettePreservesOrderAndGroupBoundaries() {
        let palette = EditorChrome(tools: ["image", "arrow", "unknown", "oval", "select", "arrow", "blur", "crop"])
        #expect(palette.tools == ["image", "arrow", "oval", "select", "blur", "crop"])
        #expect(palette.tools.indices.filter { palette.beginsGroup(at: $0) } == [1, 3, 4, 5])
        #expect(EditorChrome(tools: []).tools.isEmpty)
        #expect(Set(EditorChrome().tools) == Set(ToolRegistry.tools.map { $0.kind.rawValue } + ["select", "crop", "picker", "image"]))
    }

    @Test @MainActor func hiddenToolsStillRespondToCustomShortcuts() throws {
        let model = EditorModel(document: CaptureDocument(original: try Self.solid(32, 32), width: 32, height: 32))
        let chrome = EditorChrome(tools: ["select"])
        #expect(!chrome.tools.contains("rectangle"))
        model.toolShortcuts = ["rectangle": "j"]
        let canvas = CanvasView(model: model)
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "j", charactersIgnoringModifiers: "j", isARepeat: false, keyCode: 38))
        canvas.keyDown(with: event)
        #expect(model.tool == "rectangle")
    }

    @Test @MainActor func writeFeedbackWaitsForCompletionAndDistinguishesCancellation() async throws {
        let model = EditorModel(document: CaptureDocument(original: try Self.solid(32, 32), width: 32, height: 32))
        var finish: CheckedContinuation<EditorWriteResult, Never>?
        model.copyAction = { _ in await withCheckedContinuation { finish = $0 } }
        model.export(copy: true)
        try await settle { finish != nil }
        #expect(model.busy && model.exportFeedback == nil)
        try #require(finish).resume(returning: .written)
        try await settle { !model.busy }
        #expect(model.exportFeedback == EditorExportFeedback(copy: true, succeeded: true))
        model.saveAction = { _, _, _ in .failed("Disk full") }
        model.export()
        try await settle { !model.busy }
        #expect(model.exportFeedback == EditorExportFeedback(copy: false, succeeded: false))
        #expect(model.status == "Disk full")
        model.saveAction = { _, _, _ in .cancelled }
        model.export()
        try await settle { !model.busy }
        #expect(model.exportFeedback == nil)
    }

    @Test @MainActor func backdropCrossfadesOnlyForDiscreteChanges() async throws {
        let model = EditorModel(document: CaptureDocument(original: try Self.solid(48, 48), width: 48, height: 48))
        model.commit { $0.backdrop.fill = .solid }
        try await settle { model.renderedBackdropRevision == 1 }
        model.previewChange { $0.backdrop.padding = 20 }
        model.commitDraft()
        try await settle { model.image?.width == 88 }
        #expect(model.renderedBackdropRevision == 1 && model.image?.width == 88)
        model.commit { $0.backdrop.ratio = 2 }
        try await settle { model.renderedBackdropRevision == 2 }
        #expect(model.renderedBackdropRevision == 2)
        model.zoom = 1.5
        #expect(model.zoomCommand == 0)
        model.zoomToFit()
        #expect(model.zoomCommand == 1)
    }
}
