import AppKit
import SwiftUI
import QuartzCore
import Document
import Render
import DesignSystem

struct EditorCanvas: NSViewRepresentable {
    let model: EditorModel
    func makeNSView(context: Context) -> CanvasView { CanvasView(model: model) }
    func updateNSView(_ view: CanvasView, context: Context) {
        // Reading these registers them with Observation so the canvas updates when they change.
        _ = model.image; _ = model.selected; _ = model.zoom; _ = model.pan; _ = model.draft; _ = model.rasterExcluded
        _ = model.inspector; _ = model.showBackdrop; _ = model.tool; _ = model.recognition
        _ = model.pickingAskRegion; _ = model.highlightedAskRegion; _ = model.ask?.regions.last?.id
        view.sync()
    }
}

/// The editing surface.
///
/// The rendered document sits in a `CALayer`, so panning and zooming only move a layer and never redraw pixels.
/// Selected layers, layers being drawn, handles, and guides are painted by a lightweight overlay on every pointer event.
@MainActor final class CanvasView: NSView {
    let model: EditorModel
    private let checkerLayer = CALayer()
    private let imageLayer = CALayer()
    private let overlay = CanvasOverlay()

    private let askGuide = AskRegionGuide()
    private var askHost: AskGuideHost?
    private var askStart: CGPoint?
    private var askRect: CGRect?
    private var wasPicking = false
    private var start: CGPoint?
    private var points: [CGPoint] = []
    private var original: CaptureDocument?
    private var drawingID = UUID()
    private enum Grab { case corner(Int), endpoint(Int) }
    private var grab: Grab?
    private var dragPan: CGPoint?
    private var displayedImage: CGImage?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(model: EditorModel) {
        self.model = model
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        checkerLayer.backgroundColor = Self.checkerColor()
        checkerLayer.shadowColor = NSColor.black.cgColor
        checkerLayer.shadowOpacity = 0.3; checkerLayer.shadowRadius = 22; checkerLayer.shadowOffset = CGSize(width: 0, height: 10)
        imageLayer.contentsGravity = .resize
        imageLayer.minificationFilter = .trilinear
        layer?.addSublayer(checkerLayer)
        layer?.addSublayer(imageLayer)
        overlay.canvas = self
        addSubview(overlay)
        registerForDraggedTypes([.fileURL, .png, .tiff])
        setAccessibilityRole(.image)
        setAccessibilityLabel("Screenshot editing canvas")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// A small two-tone tile, visible only where the image is transparent.
    private static func checkerColor() -> CGColor {
        let tile: CGFloat = 8
        let image = NSImage(size: CGSize(width: tile * 2, height: tile * 2), flipped: false) { _ in
            NSColor(white: 0.5, alpha: 0.10).setFill()
            CGRect(x: 0, y: 0, width: tile, height: tile).fill()
            CGRect(x: tile, y: tile, width: tile, height: tile).fill()
            return true
        }
        return NSColor(patternImage: image).cgColor
    }

    // MARK: Geometry

    fileprivate var geometry: DocumentRenderer.Layout { DocumentRenderer.layout(model.current) }
    /// The area left free by the floating panels and bars.
    private var available: CGRect {
        let left = model.showBackdrop ? DS.backdropPanelWidth + DS.edge + DS.canvasMargin : DS.canvasMargin
        let panelWidth = model.inspector == "ask" ? DS.Ask.editorWidth : DS.sidePanelWidth
        let right = model.inspector.isEmpty ? DS.canvasMargin : panelWidth + DS.edge + DS.canvasMargin
        return CGRect(x: left, y: DS.canvasTop, width: max(100, bounds.width - left - right),
                      height: max(100, bounds.height - DS.canvasTop - DS.canvasBottom))
    }
    fileprivate var factor: CGFloat {
        model.zoom > 0 ? model.zoom : min(1, min(available.width / geometry.size.width, available.height / geometry.size.height))
    }
    fileprivate var imageRect: CGRect {
        let size = CGSize(width: geometry.size.width * factor, height: geometry.size.height * factor)
        return CGRect(x: available.midX - size.width / 2 + model.pan.x, y: available.midY - size.height / 2 + model.pan.y,
                      width: size.width, height: size.height)
    }
    private func imagePoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil), r = imageRect, l = geometry
        return CGPoint(x: (p.x - r.minX) / factor - l.content.minX + l.crop.minX,
                       y: (p.y - r.minY) / factor - l.content.minY + l.crop.minY)
    }
    fileprivate func viewPoint(_ point: CGPoint) -> CGPoint {
        let r = imageRect, l = geometry
        return CGPoint(x: r.minX + (point.x + l.content.minX - l.crop.minX) * factor, y: r.minY + (point.y + l.content.minY - l.crop.minY) * factor)
    }
    fileprivate func viewRect(_ rect: CGRect) -> CGRect {
        let origin = viewPoint(rect.origin)
        return CGRect(x: origin.x, y: origin.y, width: rect.width * factor, height: rect.height * factor)
    }
    fileprivate func corners(of rect: CGRect) -> [CGPoint] {
        [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
         CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
    }
    /// Lines, arrows, and rulers are edited by their two ends instead of a bounding box.
    fileprivate static func hasEndpoints(_ layer: Layer) -> Bool {
        [.line, .arrow, .ruler].contains(layer.kind) && layer.points.count == 2 && layer.rotation == 0
    }

    // MARK: Layout and display

    override func layout() { super.layout(); sync() }

    /// Positions the image layer and repaints the overlay. Cheap enough to call on every pointer event.
    func sync() {
        let rect = imageRect
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if displayedImage !== model.image { imageLayer.contents = model.image; displayedImage = model.image }
        imageLayer.frame = rect
        imageLayer.magnificationFilter = factor >= 3 ? .nearest : .linear
        checkerLayer.frame = rect
        checkerLayer.shadowPath = CGPath(rect: CGRect(origin: .zero, size: rect.size), transform: nil)
        CATransaction.commit()
        syncAskGuide()
        overlay.frame = bounds
        overlay.needsDisplay = true
        if abs(model.displayScale - factor) > 0.0001 {
            let value = Double(factor)
            DispatchQueue.main.async { [model] in model.displayScale = value }
        }
        window?.invalidateCursorRects(for: self)
    }

    private func syncAskGuide() {
        if model.pickingAskRegion && !wasPicking { window?.makeFirstResponder(self) }
        wasPicking = model.pickingAskRegion
        if !wasPicking { askStart = nil; askRect = nil }
        var mark: AskRegionGuide.Mark?
        if model.inspector == "ask", let ask = model.ask {
            if let rect = askRect, !rect.isEmpty {
                mark = .init(rect: viewRect(rect), label: "Region \(ask.nextRegion) · \(Int(rect.width)) × \(Int(rect.height))")
            } else if let rect = model.highlightedAskRegion {
                mark = .init(rect: viewRect(rect), label: nil)
            } else if let region = ask.regions.last, region.document == model.document {
                mark = .init(rect: viewRect(region.rect), label: region.label)
            }
        }
        if mark != nil, askHost == nil {
            let host = AskGuideHost(rootView: AskRegionOverlay(guide: askGuide))
            host.sizingOptions = []; addSubview(host); askHost = host
        }
        if let askHost, askHost.frame != bounds { askHost.frame = bounds }
        if askGuide.mark != mark { askGuide.mark = mark }
    }

    private func finishAskRegion() {
        if let rect = askRect, !rect.isEmpty { model.ask?.attach(rect, in: model.current) }
        model.pickingAskRegion = false
        syncAskGuide()
    }

    override func resetCursorRects() {
        let cursor: NSCursor = model.pickingAskRegion ? .crosshair : model.tool == "select" ? .arrow : model.tool == "text" ? .iBeam : .crosshair
        addCursorRect(imageRect.intersection(bounds), cursor: cursor)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if model.inspector == "ask", model.pickingAskRegion || event.modifierFlags.contains(.command) {
            let point = imagePoint(event)
            if model.document.visibleBounds.contains(point) {
                model.pickingAskRegion = true; askStart = point; askRect = nil; syncAskGuide()
            }
            return
        }
        if model.textPoint != nil { model.addText() }
        let point = imagePoint(event), location = convert(event.locationInWindow, from: nil)
        guard model.document.visibleBounds.insetBy(dx: -10, dy: -10).contains(point) else {
            dragPan = location
            if model.tool == "select" { model.selected = [] }
            return
        }
        start = point; points = [point]; original = model.document; drawingID = UUID(); grab = nil
        switch model.tool {
        case "picker":
            model.pickColor(at: point); start = nil
        case "liveText":
            if let region = model.recognition?.text.first(where: { $0.rect.contains(point) }) { model.copyText(region.text) }
            start = nil
        case "select":
            if let layer = model.document.layers.first(where: { model.selected.contains($0.id) }), model.selected.count == 1 {
                if Self.hasEndpoints(layer), let index = layer.points.firstIndex(where: { hypot(viewPoint($0).x - location.x, viewPoint($0).y - location.y) < DS.md }) {
                    grab = .endpoint(index); return
                }
                if !Self.hasEndpoints(layer), let index = corners(of: viewRect(layer.rect).insetBy(dx: -DS.xs, dy: -DS.xs)).firstIndex(where: { hypot($0.x - location.x, $0.y - location.y) < DS.md }) {
                    grab = .corner(index); return
                }
            }
            if let hit = model.document.layers.reversed().first(where: { $0.contains(point, tolerance: 8 / factor) }) {
                if event.clickCount == 2, hit.kind == .text {
                    model.selected = [hit.id]; model.beginEditingText(hit, at: viewPoint(hit.rect.origin)); start = nil; return
                }
                if event.modifierFlags.contains(.shift) {
                    if model.selected.contains(hit.id) { model.selected.remove(hit.id) } else { model.selected.insert(hit.id) }
                } else if !model.selected.contains(hit.id) { model.selected = [hit.id] }
            } else {
                if !event.modifierFlags.contains(.shift) { model.selected = [] }
                overlay.marquee = CGRect(origin: point, size: .zero)
            }
        case "text":
            model.textInput = ""; model.textPoint = point; model.textViewPoint = location
            start = nil
        case "counter":
            let number = (model.document.layers.filter { $0.kind == .counter }.compactMap { Int($0.text) }.max() ?? 0) + 1
            let style = model.style, size = max(36, style.fontSize * 1.6)
            let layer = Layer(kind: .counter, rect: CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size),
                              color: style.color, opacity: style.opacity, text: String(number), fontSize: style.fontSize)
            model.commit { $0.layers.append(layer) }; start = nil
        default: break
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if let askStart, model.pickingAskRegion {
            let end = imagePoint(event)
            askRect = CGRect(x: askStart.x, y: askStart.y, width: end.x - askStart.x, height: end.y - askStart.y)
                .standardized.integral.intersection(model.document.visibleBounds)
            syncAskGuide()
            return
        }
        if let previous = dragPan {
            let next = convert(event.locationInWindow, from: nil)
            model.pan.x += next.x - previous.x; model.pan.y += next.y - previous.y; dragPan = next
            sync(); return
        }
        guard let start, var doc = original else { return }
        var end = imagePoint(event)
        end.x = max(0, min(CGFloat(doc.width), end.x)); end.y = max(0, min(CGFloat(doc.height), end.y))
        if event.modifierFlags.contains(.shift), grab == nil, overlay.marquee == nil {
            let dx = end.x - start.x, dy = end.y - start.y
            if model.tool == "select" { if abs(dx) > abs(dy) { end.y = start.y } else { end.x = start.x } }   // move along one axis
            else { let side = max(abs(dx), abs(dy)); end = CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side)) }
        }
        if model.tool == "select" {
            if overlay.marquee != nil {
                let band = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
                overlay.marquee = band
                model.selected = Set(doc.layers.filter { $0.rect.intersects(band) }.map(\.id))
                overlay.needsDisplay = true; return
            }
            var delta = CGPoint(x: end.x - start.x, y: end.y - start.y)
            if grab == nil { delta = snapped(delta, moving: doc.layers.filter { model.selected.contains($0.id) }, in: doc, disabled: event.modifierFlags.contains(.command)) }
            for i in doc.layers.indices where model.selected.contains(doc.layers[i].id) {
                switch grab {
                case .endpoint(let index):
                    doc.layers[i].points[index] = end
                    let a = doc.layers[i].points[0], b = doc.layers[i].points[1]
                    doc.layers[i].rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: max(1, abs(a.x - b.x)), height: max(1, abs(a.y - b.y)))
                case .corner(let corner):
                    // Keep the opposite corner fixed and move the dragged one with the pointer.
                    let all = corners(of: doc.layers[i].rect), anchor = all[3 - corner]
                    let moved = CGPoint(x: all[corner].x + delta.x, y: all[corner].y + delta.y)
                    doc.layers[i].resize(to: CGRect(x: min(anchor.x, moved.x), y: min(anchor.y, moved.y),
                                                    width: max(4, abs(moved.x - anchor.x)), height: max(4, abs(moved.y - anchor.y))))
                case nil:
                    doc.layers[i].translate(x: delta.x, y: delta.y)
                }
            }
            model.preview(doc)
        } else if model.tool == "crop" {
            overlay.crop = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
            overlay.needsDisplay = true
        } else if let tool = ToolRegistry.tool(model.tool) {
            points.append(end)
            let freehand = tool.kind == .drawing || tool.kind == .highlighter
            let path = freehand ? points : [start, end]
            var layer = tool.makeLayer(start: start, end: end, points: path, style: model.style)
            layer.id = drawingID
            if freehand {
                let xs = path.map(\.x), ys = path.map(\.y)
                layer.rect = CGRect(x: xs.min() ?? start.x, y: ys.min() ?? start.y,
                                    width: max(1, (xs.max() ?? end.x) - (xs.min() ?? start.x)),
                                    height: max(1, (ys.max() ?? end.y) - (ys.min() ?? start.y)))
            }
            if tool.kind == .erase, let source = DocumentRenderer.decode(doc.original) {
                layer.color = DocumentRenderer.sample(source, at: CGPoint(x: max(0, start.x - 2), y: max(0, start.y - 2)))
            }
            doc.layers.append(layer)
            model.preview(doc, live: EditorModel.drawsLive(layer.kind) ? layer.id : nil)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if askStart != nil, model.pickingAskRegion {
            mouseDragged(with: event); finishAskRegion(); return
        }
        defer { start = nil; original = nil; points = []; dragPan = nil; grab = nil; overlay.crop = nil; overlay.marquee = nil; overlay.guides = []; overlay.needsDisplay = true }
        if let crop = overlay.crop, crop.width > 2, crop.height > 2 { model.commit { $0.crop = crop }; model.tool = "select"; return }
        if let draft = model.draft {
            let before = Set(model.document.layers.map(\.id))
            model.commit { $0 = draft }
            // Select what was just drawn so its options can be adjusted right away.
            if model.tool != "select", let added = model.document.layers.last, !before.contains(added.id) { model.selected = [added.id] }
        }
    }

    /// Pulls a move onto the image's edges and center lines when it comes within a few points of them.
    private func snapped(_ delta: CGPoint, moving: [Layer], in doc: CaptureDocument, disabled: Bool) -> CGPoint {
        overlay.guides = []
        guard !disabled, let first = moving.first else { return delta }
        let box = moving.dropFirst().reduce(first.rect) { $0.union($1.rect) }.offsetBy(dx: delta.x, dy: delta.y)
        let area = doc.visibleBounds, reach = 6 / factor
        var result = delta
        for (value, target) in [(box.midX, area.midX), (box.minX, area.minX), (box.maxX, area.maxX)] where abs(value - target) < reach {
            result.x += target - value; overlay.guides.append((vertical: true, position: target)); break
        }
        for (value, target) in [(box.midY, area.midY), (box.minY, area.minY), (box.maxY, area.maxY)] where abs(value - target) < reach {
            result.y += target - value; overlay.guides.append((vertical: false, position: target)); break
        }
        return result
    }

    override func magnify(with event: NSEvent) { model.zoom = max(0.1, min(32, factor * (1 + event.magnification))); sync() }
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) { model.zoom = max(0.1, min(32, factor * exp(-event.scrollingDeltaY / 150))) }
        else { model.pan.x += event.scrollingDeltaX; model.pan.y += event.scrollingDeltaY }
        sync()
    }

    // MARK: Keyboard

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, event.modifierFlags.contains(.command),
              let key = event.charactersIgnoringModifiers?.lowercased() else { return super.performKeyEquivalent(with: event) }
        switch key {
        case "z": event.modifierFlags.contains(.shift) ? model.redo() : model.undo()
        case "c": model.export(copy: true)
        case "s": event.modifierFlags.contains(.shift) ? model.saveProject() : model.export()
        case "v": model.pasteImage()
        case "d": model.duplicateSelection()
        case "a": model.tool = "select"; model.selected = Set(model.document.layers.map(\.id))
        case "0": model.zoomToFit()
        case "1": model.zoom = 1; model.pan = .zero
        case "=", "+": model.zoom(by: 1.25)
        case "-": model.zoom(by: 0.8)
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    override func keyDown(with event: NSEvent) {
        if model.pickingAskRegion {
            if event.keyCode == 53 { model.pickingAskRegion = false; syncAskGuide() }
            else if event.keyCode == 36 { finishAskRegion() }
            return
        }
        if event.keyCode == 53 { model.preview(nil); model.selected = []; start = nil; overlay.crop = nil; model.cancelText(); return }
        if event.keyCode == 51 || event.keyCode == 117 { model.deleteSelection(); return }
        if (123...126).contains(event.keyCode) {
            let amount: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            let dx: CGFloat = event.keyCode == 123 ? -amount : event.keyCode == 124 ? amount : 0
            let dy: CGFloat = event.keyCode == 126 ? -amount : event.keyCode == 125 ? amount : 0
            model.modifySelected { $0.translate(x: dx, y: dy) }; return
        }
        guard let key = event.charactersIgnoringModifiers?.lowercased(), !event.modifierFlags.contains(.command) else { super.keyDown(with: event); return }
        func bound(_ id: String, _ fallback: String) -> Bool { key == (model.toolShortcuts[id] ?? fallback) }
        if let tool = ToolRegistry.tools.first(where: { bound($0.kind.rawValue, $0.shortcut) }) { model.selected = []; model.tool = tool.kind.rawValue }
        else if bound("select", "v") { model.tool = "select" }
        else if bound("crop", "c") { model.tool = "crop" }
        else if bound("picker", "i") { model.tool = "picker" }
        else { super.keyDown(with: event) }
    }

    // MARK: Drag and drop

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let board = sender.draggingPasteboard
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let url = urls.first, let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            model.addImage(image); return true
        }
        if let image = NSImage(pasteboard: board)?.cgImage(forProposedRect: nil, context: nil, hints: nil) { model.addImage(image); return true }
        return false
    }
}

/// Paints everything that changes with the pointer: live layers, selection handles, guides, crop, and marquee.
@MainActor private final class CanvasOverlay: NSView {
    weak var canvas: CanvasView?
    var crop: CGRect?
    var marquee: CGRect?
    var guides: [(vertical: Bool, position: CGFloat)] = []

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let canvas, let context = NSGraphicsContext.current?.cgContext else { return }
        let model = canvas.model, doc = model.current, factor = canvas.factor, rect = canvas.imageRect

        // Layers the raster leaves out, painted in image coordinates and clipped to the image like the export.
        let live = doc.layers.filter { model.rasterExcluded.contains($0.id) }
        if !live.isEmpty {
            let origin = canvas.viewPoint(.zero)
            context.saveGState()
            context.clip(to: canvas.viewRect(doc.visibleBounds))
            context.translateBy(x: origin.x, y: origin.y); context.scaleBy(x: factor, y: factor)
            DocumentRenderer.drawLive(live, document: doc, scale: factor, context: context)
            context.restoreGState()
        }
        if factor >= 8 { drawPixelGrid(in: rect, factor: factor, context: context) }
        for layer in doc.layers where model.selected.contains(layer.id) { drawSelection(layer, single: model.selected.count == 1, canvas: canvas, context: context) }
        if model.tool == "liveText", let recognition = model.recognition {
            for region in recognition.text {
                let box = NSBezierPath(roundedRect: canvas.viewRect(region.rect).insetBy(dx: -2, dy: -2), xRadius: 3, yRadius: 3)
                DS.nsAccent.withAlphaComponent(0.16).setFill(); box.fill()
                DS.nsAccent.withAlphaComponent(0.7).setStroke(); box.lineWidth = DS.stroke; box.stroke()
            }
        }
        if !guides.isEmpty {
            context.setStrokeColor(NSColor.systemPink.cgColor); context.setLineWidth(1)
            for guide in guides {
                let point = canvas.viewPoint(CGPoint(x: guide.position, y: guide.position))
                if guide.vertical { context.move(to: CGPoint(x: point.x, y: rect.minY)); context.addLine(to: CGPoint(x: point.x, y: rect.maxY)) }
                else { context.move(to: CGPoint(x: rect.minX, y: point.y)); context.addLine(to: CGPoint(x: rect.maxX, y: point.y)) }
            }
            context.strokePath()
        }
        if let marquee {
            let band = canvas.viewRect(marquee)
            context.setFillColor(DS.nsAccent.withAlphaComponent(0.12).cgColor); context.fill(band)
            context.setStrokeColor(DS.nsAccent.cgColor); context.setLineWidth(1); context.stroke(band)
        }
        if let crop { drawCrop(canvas.viewRect(crop), image: rect, context: context) }
    }

    private func drawPixelGrid(in rect: CGRect, factor: CGFloat, context: CGContext) {
        context.saveGState(); context.clip(to: rect)
        context.setStrokeColor(NSColor.labelColor.withAlphaComponent(DS.outlineOpacity).cgColor)
        context.setLineWidth(0.5)
        for x in stride(from: rect.minX + max(0, floor(-rect.minX / factor)) * factor, to: min(bounds.maxX, rect.maxX), by: factor) {
            context.move(to: CGPoint(x: x, y: max(0, rect.minY))); context.addLine(to: CGPoint(x: x, y: min(bounds.maxY, rect.maxY)))
        }
        for y in stride(from: rect.minY + max(0, floor(-rect.minY / factor)) * factor, to: min(bounds.maxY, rect.maxY), by: factor) {
            context.move(to: CGPoint(x: max(0, rect.minX), y: y)); context.addLine(to: CGPoint(x: min(bounds.maxX, rect.maxX), y: y))
        }
        context.strokePath(); context.restoreGState()
    }

    private func drawSelection(_ layer: Layer, single: Bool, canvas: CanvasView, context: CGContext) {
        if CanvasView.hasEndpoints(layer) {
            if single { for point in layer.points { handle(at: canvas.viewPoint(point), context: context) } }
            else { for point in layer.points { dot(at: canvas.viewPoint(point), context: context) } }
            return
        }
        let rect = canvas.viewRect(layer.rect).insetBy(dx: -DS.xs, dy: -DS.xs)
        context.setStrokeColor(DS.nsAccent.cgColor); context.setLineWidth(DS.overlayLine); context.stroke(rect)
        if single { for corner in canvas.corners(of: rect) { handle(at: corner, context: context) } }
    }
    private func handle(at point: CGPoint, context: CGContext) {
        let frame = CGRect(x: point.x - DS.selectionHandle / 2, y: point.y - DS.selectionHandle / 2, width: DS.selectionHandle, height: DS.selectionHandle)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -1), blur: 3, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        context.setFillColor(NSColor.white.cgColor); context.fillEllipse(in: frame)
        context.restoreGState()
        context.setStrokeColor(DS.nsAccent.cgColor); context.setLineWidth(DS.overlayLine); context.strokeEllipse(in: frame)
    }
    private func dot(at point: CGPoint, context: CGContext) {
        context.setFillColor(DS.nsAccent.cgColor)
        context.fillEllipse(in: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6))
    }

    private func drawCrop(_ rect: CGRect, image: CGRect, context: CGContext) {
        // Dim what will be removed, then draw a rule-of-thirds frame.
        context.saveGState()
        context.addRect(image); context.addRect(rect)
        context.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
        context.fillPath(using: .evenOdd)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor); context.setLineWidth(0.5)
        for i in 1...2 {
            let x = rect.minX + rect.width * CGFloat(i) / 3, y = rect.minY + rect.height * CGFloat(i) / 3
            context.move(to: CGPoint(x: x, y: rect.minY)); context.addLine(to: CGPoint(x: x, y: rect.maxY))
            context.move(to: CGPoint(x: rect.minX, y: y)); context.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        context.strokePath()
        context.setStrokeColor(NSColor.white.cgColor); context.setLineWidth(DS.overlayLine); context.stroke(rect)
        context.restoreGState()
    }
}
