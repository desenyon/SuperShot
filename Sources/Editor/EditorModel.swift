import AppKit
import CoreText
import Observation
import Document
import Render
import Export
import DesignSystem
import Recognition
import AI

public enum EditorWriteResult: Equatable, Sendable {
    case written, cancelled, failed(String)
}

struct EditorExportFeedback: Equatable {
    let copy: Bool
    let succeeded: Bool
}

@MainActor @Observable public final class EditorModel {
    private var history: DocumentHistory
    public var document: CaptureDocument { history.document }
    public var canUndo: Bool { history.canUndo }
    public var canRedo: Bool { history.canRedo }
    public var image: CGImage?
    public var draft: CaptureDocument?
    public var selected: Set<UUID> = [] { didSet { if oldValue != selected { updateLiveLayers() } } }
    /// Layers left out of `image`. The canvas draws these directly, so moving or restyling them costs no re-render.
    public private(set) var rasterExcluded: Set<UUID> = []
    /// The text layer being retyped inline, if any.
    public var editingText: UUID?
    public var tool = "arrow" { didSet { if oldValue != tool { styles[oldValue] = style; style = styles[tool] ?? ToolStyle() } } }
    public var style = ToolStyle()
    /// The active right-hand panel, or an empty identifier when the panel is closed.
    public var inspector = "" {
        didSet { if inspector != "ask" { pickingAskRegion = false } }
    }
    public var ask: AskModel?
    public var askOptions: AskOptions?
    public var assistantFactory: AssistantFactory?
    public var pickingAskRegion = false
    public var highlightedAskRegion: CGRect?
    @ObservationIgnored private var highlightTask: Task<Void, Never>?

    @discardableResult public func openAsk() -> AskModel? {
        guard let ask = prepareAsk() else { return nil }
        inspector = "ask"
        return ask
    }

    /// A conversation kept with this capture, shown when Ask first opens.
    public var restoredAskMessages: [AskMessage] = []
    /// Lets the app attach persistence to each conversation this editor creates.
    @ObservationIgnored public var configureAsk: (@MainActor (AskModel) -> Void)?

    public func prepareAsk() -> AskModel? {
        guard let askOptions, let assistantFactory else { return nil }
        if ask == nil {
            let created = AskModel(options: askOptions, factory: assistantFactory, messages: restoredAskMessages)
            configureAsk?(created); ask = created
        }
        return ask
    }

    public func flashAskRegion(_ rect: CGRect) {
        highlightTask?.cancel()
        highlightedAskRegion = rect
        highlightTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)); self?.highlightedAskRegion = nil } catch {}
        }
    }

    func addReply(_ text: String) {
        let bounds = document.visibleBounds
        let inset = min(bounds.width, bounds.height) * 0.06
        let area = bounds.insetBy(dx: inset, dy: inset)
        var fontSize = min(style.fontSize, area.height / 1.4)
        var lines: [String] = []
        // The renderer draws explicit lines. Break with Core Text so the editable layer fits
        // inside the visible crop even when a reply is much longer than the capture is wide.
        while fontSize > 0 {
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize, weight: .semibold)]
            lines = text.components(separatedBy: .newlines).flatMap { paragraph -> [String] in
                let source = paragraph as NSString
                let typesetter = CTTypesetterCreateWithAttributedString(NSAttributedString(string: paragraph, attributes: attributes))
                var start = 0, wrapped: [String] = []
                while start < source.length {
                    let count = max(1, CTTypesetterSuggestLineBreak(typesetter, start, area.width))
                    wrapped.append(source.substring(with: NSRange(location: start, length: count)))
                    start += count
                }
                return wrapped.isEmpty ? [""] : wrapped
            }
            if CGFloat(lines.count) * fontSize * 1.25 <= area.height || fontSize <= 1 { break }
            fontSize *= 0.8
        }
        let height = min(area.height, CGFloat(lines.count) * fontSize * 1.25)
        let rect = CGRect(origin: area.origin, size: CGSize(width: area.width, height: height))
        let layer = Layer(kind: .text, rect: rect, color: style.color, text: lines.joined(separator: "\n"), fontSize: fontSize)
        commit { $0.layers.append(layer) }
        selected = [layer.id]; tool = "select"
    }
    /// Left-hand backdrop panel.
    public var showBackdrop = true
    /// Where the inline text field sits, in canvas view coordinates.
    public var textViewPoint: CGPoint?
    /// Actual on-screen scale of the canvas, reported by the canvas view.
    public var displayScale: Double = 1
    public var zoom: Double = 0 { didSet { if oldValue != zoom {refresh()} } } // zero fits; positive values inspect image pixels
    public var pan = CGPoint.zero
    public var message: String?
    public var busy = false
    public var textPoint: CGPoint?
    public var textInput = ""
    public var format = "public.png"
    public var outputMultiplier: Double = 1
    public var colorFormat = "hex"
    public var toolShortcuts: [String: String] = [:]
    public var saveBackdropAction: ((Backdrop) -> Void)?
    public var savedPresets: [BackdropPreset] = []
    public var presetName = ""
    public var savePresetAction: ((String,Backdrop) -> Void)?
    public var status = ""
    var exportFeedback: EditorExportFeedback?
    public var copyAction: ((CGImage) async -> EditorWriteResult)?
    public var saveAction: ((CGImage, String, CaptureDocument) async -> EditorWriteResult)?
    public var pinAction: ((CGImage) -> Void)?
    public var autosaveAction: ((CaptureDocument) -> Void)?
    public var recognition: RecognitionResult?
    public var redactions: [RedactionCandidate] = []
    public var acceptedRedactions: Set<UUID> = []
    public var aiPrompt = ""
    public var translationLanguage = "en"
    public var generatedText = ""
    @ObservationIgnored private let recognizer = RecognitionService()
    @ObservationIgnored private let ai: any AIProvider = LocalAIProvider()
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var styles: [String: ToolStyle] = [:]
    @ObservationIgnored private var liveIDs: Set<UUID> = []
    @ObservationIgnored private var rendering = false
    @ObservationIgnored private var pendingRender = false
    @ObservationIgnored private var interacting = false
    @ObservationIgnored private var lastRaster: (document: CaptureDocument, factor: Double)?
    @ObservationIgnored public private(set) var generation = 0
    @ObservationIgnored private var backdropRevision = 0
    @ObservationIgnored private(set) var renderedBackdropRevision = 0
    private(set) var zoomCommand = 0

    public init(document: CaptureDocument) {
        history = DocumentHistory(document: document)
        image = DocumentRenderer.decode(document.original)
        refresh()
    }
    public func commit(_ change: (inout CaptureDocument) -> Void) {
        let previous = document.backdrop
        history.change(change)
        if draft == nil && document.backdrop != previous { backdropRevision &+= 1 }
        draft = nil; interacting = false; invalidateAnalysis(); refresh(); scheduleSave()
    }
    public func undo() { restoreHistory(undo: true) }
    public func redo() { restoreHistory(undo: false) }

    private func restoreHistory(undo: Bool) {
        let previous = document.backdrop
        draft = nil
        interacting = false
        if undo { history.undo() } else { history.redo() }
        if document.backdrop != previous { backdropRevision &+= 1 }
        selected = []
        invalidateAnalysis()
        refresh()
        scheduleSave()
    }
    private func invalidateAnalysis() {
        recognition=nil; redactions=[]; acceptedRedactions=[]; generatedText=""; status=""
    }
    /// Shows an uncommitted change. `live` names a layer that is being drawn and should be painted by the canvas.
    public func preview(_ document: CaptureDocument?, live: UUID? = nil) {
        draft = document; interacting = document != nil
        if let live { liveIDs.insert(live) }
        refresh()
    }
    /// The document as it currently appears, including an uncommitted drag.
    public var current: CaptureDocument { draft ?? document }
    /// Applies a change without recording undo history. Follow with `commitDraft()`.
    public func previewChange(_ change: (inout CaptureDocument) -> Void) {
        var next = draft ?? document; change(&next); preview(next)
    }
    public func commitDraft() { if let draft { commit { $0 = draft } } else if interacting { interacting = false; refresh() } }
    /// Updates the active tool style and any selected layers. `live` previews without adding undo steps.
    public func restyle(live: Bool = false, _ update: (inout ToolStyle) -> Void, layers apply: @escaping (inout Layer) -> Void) {
        update(&style)
        guard !selected.isEmpty else { return }
        let ids = selected
        let change: (inout CaptureDocument) -> Void = { doc in for i in doc.layers.indices where ids.contains(doc.layers[i].id) { apply(&doc.layers[i]) } }
        if live { previewChange(change) } else { commit(change) }
    }
    public var selectedLayer: Layer? { current.layers.first { selected.contains($0.id) } }
    public func zoom(by factor: Double) { zoomCommand &+= 1; zoom = max(0.1, min(32, (zoom == 0 ? displayScale : zoom) * factor)) }
    public func zoomToFit() { setZoom(0) }
    func setZoom(_ value: Double) {
        zoomCommand &+= 1
        zoom = value
        pan = .zero
    }
    public func cancelText() { textPoint = nil; textViewPoint = nil; textInput = ""; editingText = nil }

    // MARK: Rendering

    /// Layer kinds the canvas can paint directly. Blur, pixelate, and magnifier sample the pixels beneath them, so they stay in the raster.
    public static func drawsLive(_ kind: LayerKind) -> Bool { ![.blur, .pixelate, .magnifier].contains(kind) }

    private func updateLiveLayers() {
        liveIDs = Set(current.layers.filter { selected.contains($0.id) && Self.drawsLive($0.kind) }.map(\.id))
        refresh()
    }
    /// Requests a new raster. Requests made while one is rendering collapse into a single follow-up,
    /// and every finished frame is shown, so a continuous drag keeps updating instead of waiting for the pointer to stop.
    public func refresh() {
        generation += 1
        if rendering { pendingRender = true } else { startRender() }
    }
    private func startRender() {
        var trimmed = current
        let live = liveIDs.intersection(trimmed.layers.filter { Self.drawsLive($0.kind) }.map(\.id))
        trimmed.layers.removeAll { live.contains($0.id) }
        let revision = backdropRevision
        let snapshot = trimmed
        let size = DocumentRenderer.layout(snapshot).size, longest = max(size.width, size.height)
        // A lighter raster while a control is being dragged; full preview quality as soon as it is released.
        let factor = interacting ? min(1, 1280 / longest) : max(min(1, zoom), min(1, 2200 / longest))
        if let lastRaster, lastRaster.factor == factor, Self.sameRaster(lastRaster.document, snapshot) { rasterExcluded = live; return }
        rendering = true
        Task { [weak self] in
            let output: (image: CGImage?, error: String?) = await Task.detached(priority: .userInitiated) {
                do { return (try DocumentRenderer.render(snapshot, scale: factor), nil) } catch { return (nil, error.localizedDescription) }
            }.value
            guard let self else { return }
            self.rendering = false
            if let image = output.image { self.renderedBackdropRevision = revision; self.image = image; self.rasterExcluded = live; self.lastRaster = (snapshot, factor) }
            else if !self.pendingRender, let error = output.error { self.message = error }
            if self.pendingRender { self.pendingRender = false; self.startRender() }
        }
    }
    /// Whether two documents produce the same pixels. Large image data is compared by size, since it is never edited in place.
    private static func sameRaster(_ a: CaptureDocument, _ b: CaptureDocument) -> Bool {
        var x = a.backdrop, y = b.backdrop
        let wallpapers = (x.wallpaper?.count, y.wallpaper?.count)
        x.wallpaper = nil; y.wallpaper = nil
        return a.id == b.id && a.crop == b.crop && a.layers == b.layers && x == y && wallpapers.0 == wallpapers.1
            && a.processedBase?.count == b.processedBase?.count && a.preserveColorProfile == b.preserveColorProfile
    }
    public func duplicateSelection() {
        let copies = document.layers.filter { selected.contains($0.id) }.map { layer -> Layer in
            var copy = layer; copy.id = UUID(); copy.translate(x: 24, y: 24); return copy
        }
        guard !copies.isEmpty else { return }
        commit { $0.layers.append(contentsOf: copies) }
        selected = Set(copies.map(\.id)); tool = "select"
    }
    /// Starts retyping an existing text layer in place.
    public func beginEditingText(_ layer: Layer, at viewPoint: CGPoint) {
        editingText = layer.id; textInput = layer.text; textPoint = layer.rect.origin; textViewPoint = viewPoint
    }
    public func deleteSelection() {
        let ids=selected; commit { $0.layers.removeAll { ids.contains($0.id) } }; selected=[]
    }
    public func modifySelected(_ update: (inout Layer) -> Void) {
        let ids=selected
        commit { doc in for i in doc.layers.indices where ids.contains(doc.layers[i].id) { update(&doc.layers[i]) } }
    }
    public func reorderSelected(front: Bool) {
        let ids=selected
        commit { doc in
            let matching=doc.layers.filter { ids.contains($0.id) }, other=doc.layers.filter { !ids.contains($0.id) }
            doc.layers=front ? other+matching : matching+other
        }
    }
    public func addText() {
        if let id=editingText {
            let text=textInput
            if text.isEmpty { selected=[id]; deleteSelection() }
            else { commit { doc in for i in doc.layers.indices where doc.layers[i].id == id { doc.layers[i].text=text; doc.layers[i].rect.size.width=max(40,Double(text.count)*doc.layers[i].fontSize*0.62) } } }
            cancelText(); return
        }
        guard let point=textPoint, !textInput.isEmpty else { cancelText(); return }
        let text=textInput, style=style
        var layer=Layer(kind: .text, rect: CGRect(x:point.x,y:point.y,width:max(40,Double(text.count)*style.fontSize*0.62),height:style.fontSize*1.4),color:style.color,opacity:style.opacity,text:text,fontSize:style.fontSize)
        if style.textBackground {layer.textBackground = .black};layer.textOutline=style.textOutline
        commit { $0.layers.append(layer) }; selected=[layer.id]; tool="select"; cancelText()
    }
    public func addImage(_ image: CGImage) {
        do {
            let data=try ImageExport.encode(image), size=document.visibleBounds.size
            let factor=min(1,min(size.width/CGFloat(image.width),size.height/CGFloat(image.height))*0.7)
            let rect=CGRect(x:document.visibleBounds.midX-CGFloat(image.width)*factor/2,y:document.visibleBounds.midY-CGFloat(image.height)*factor/2,width:CGFloat(image.width)*factor,height:CGFloat(image.height)*factor)
            let layer=Layer(kind:.image,rect:rect,imageData:data)
            commit { $0.layers.append(layer) }; selected=[layer.id]; tool="select"
        } catch { message=error.localizedDescription }
    }
    public func pasteImage() {
        if let image=NSImage(pasteboard:.general),let cg=image.cgImage(forProposedRect:nil,context:nil,hints:nil) { addImage(cg) }
    }
    public func export(copy: Bool = false, pin: Bool = false) {
        guard !busy else { return }
        busy = true
        exportFeedback = nil
        status = ""
        let snapshot = document, type = format, multiplier = outputMultiplier
        Task {
            defer { busy = false }
            do {
                let image = try await Task.detached(priority: .userInitiated) { try DocumentRenderer.render(snapshot, scale: multiplier) }.value
                if pin { pinAction?(image); return }
                let result = copy ? await copyAction?(image) : await saveAction?(image, type, snapshot)
                switch result {
                case .written:
                    exportFeedback = EditorExportFeedback(copy: copy, succeeded: true)
                    status = copy ? "Copied image" : "Saved image"
                case let .failed(reason):
                    exportFeedback = EditorExportFeedback(copy: copy, succeeded: false)
                    status = reason
                case .cancelled, nil: break
                }
            } catch {
                if pin { message = error.localizedDescription }
                else {
                    exportFeedback = EditorExportFeedback(copy: copy, succeeded: false)
                    status = error.localizedDescription
                }
            }
        }
    }
    public func flushAutosave() {
        guard saveTask != nil else{return}
        saveTask?.cancel();saveTask=nil;autosaveAction?(document)
    }
    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = document
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)); self?.autosaveAction?(snapshot); self?.saveTask=nil } catch {}
        }
    }
    public func recognize() {
        guard !busy else { return }
        inspector = "recognition"; busy = true
        let snapshot = document
        Task {
            defer { busy = false }
            do {
                let result = try await analyze(snapshot)
                guard document == snapshot else { return }
                recognition = result
                status = result.text.isEmpty ? "No readable text found" : "Text recognized on your Mac"
            } catch { message = error.localizedDescription }
        }
    }
    private func analyze(_ snapshot: CaptureDocument) async throws -> RecognitionResult {
        var content = snapshot; content.crop = nil; content.backdrop = Backdrop()
        let plain = content
        let image = try await Task.detached(priority: .userInitiated) { try DocumentRenderer.render(plain) }.value
        return try await recognizer.recognize(image, accurate: true)
    }
    public func performAI(_ request: AIRequest) {
        guard !busy else { return }
        busy = true; status = "Working on your Mac…"
        let snapshot = document
        Task {
            defer { busy = false }
            do {
                var plain = snapshot; plain.crop = nil; plain.backdrop = Backdrop()
                if case .removeBackground = request { plain.layers = [] }
                let content = plain
                let image = try await Task.detached(priority: .userInitiated) { try DocumentRenderer.render(content) }.value
                let result: RecognitionResult
                if let recognition { result = recognition }
                else if case .removeBackground = request { result = RecognitionResult() }
                else if case .erase = request { result = RecognitionResult() }
                else { result = try await recognizer.recognize(image, accurate: true) }
                let output = try await ai.perform(request, image: image, recognition: result)
                guard document == snapshot else { status = "Image changed; run the action again"; return }
                recognition = result
                switch output {
                case .image(let data): commit { $0.processedBase = data }
                case .layers(let layers): commit { $0.layers.append(contentsOf: layers) }
                case .text(let text): generatedText = text; inspector = "recognition"
                case .redactions(let candidates):
                    redactions = candidates; acceptedRedactions = Set(candidates.map(\.id)); inspector = "recognition"
                }
                status = "Ready"
            } catch { status = ""; message = error.localizedDescription }
        }
    }
    public func applyRedactions() {
        let layers = redactions.filter { acceptedRedactions.contains($0.id) }.map { Layer(kind: .rectangle, rect: $0.rect, color: .black, filled: true) }
        commit { $0.layers.append(contentsOf: layers) }; redactions = []; acceptedRedactions = []
    }
    public func pickColor(at point:CGPoint) {
        let snapshot=document,format=colorFormat
        Task {
            do {
                let color=try await Task.detached(priority:.userInitiated) {
                    let image=try DocumentRenderer.render(snapshot),layout=DocumentRenderer.layout(snapshot)
                    return DocumentRenderer.sample(image,at:CGPoint(x:point.x+layout.content.minX-layout.crop.minX,y:point.y+layout.content.minY-layout.crop.minY))
                }.value
                guard document == snapshot else{return}
                style.color=color
                let value:String
                switch format {
                case "rgb":value=String(format:"rgb(%d, %d, %d)",Int(color.red*255),Int(color.green*255),Int(color.blue*255))
                case "p3":let p3=color.nsColor.usingColorSpace(.displayP3) ?? color.nsColor;value=String(format:"color(display-p3 %.4f %.4f %.4f)",p3.redComponent,p3.greenComponent,p3.blueComponent)
                case "hsl":
                    let hi=max(color.red,color.green,color.blue),lo=min(color.red,color.green,color.blue),delta=hi-lo,light=(hi+lo)/2
                    let saturation=delta == 0 ? 0:delta/(1-abs(2*light-1))
                    var hue=delta == 0 ? 0:hi == color.red ? (color.green-color.blue)/delta:hi == color.green ? (color.blue-color.red)/delta+2:(color.red-color.green)/delta+4
                    hue=(hue*60+360).truncatingRemainder(dividingBy:360);value=String(format:"hsl(%.0f, %.0f%%, %.0f%%)",hue,saturation*100,light*100)
                default:value=color.hex
                }
                copyText(value);status="Copied \(value)"
            } catch {message=error.localizedDescription}
        }
    }
    public func copyText(_ text: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string); status = "Copied text"
    }
    public func saveProject() {
        let panel=NSSavePanel(); panel.nameFieldStringValue="\(document.source).supershot"
        guard panel.runModal() == .OK, let destination=panel.url else { return }
        do { try ProjectFile.encode(document).write(to:destination,options:.atomic); status="Project saved" }
        catch { message=error.localizedDescription }
    }
    public func trim(shadow:Bool=false,balance:Bool=false) {
        guard !busy else{return};busy=true
        let snapshot=document
        Task {
            defer{busy=false}
            guard let image=DocumentRenderer.decode(snapshot.processedBase ?? snapshot.original) else{return}
            let rect=await Task.detached {balance ? DocumentRenderer.balancedBounds(image):DocumentRenderer.alphaBounds(image,threshold:shadow ? 240:1)}.value
            guard document == snapshot,let rect else{return}
            commit{$0.crop=rect}
        }
    }
    public func selectWallpaper(desktop: Bool = false) {
        let source: URL?
        if desktop { source=NSScreen.main.flatMap { NSWorkspace.shared.desktopImageURL(for:$0) } }
        else {
            let panel=NSOpenPanel(); panel.allowedContentTypes=[.image]
            source=panel.runModal() == .OK ? panel.url : nil
        }
        guard let source else { return }
        do {
            let data=try Data(contentsOf:source)
            guard let image=DocumentRenderer.decode(data) else { throw DocumentRenderer.Error.invalidImage }
            let reduced=try ImageExport.transformed(image,factor:min(1,2048/Double(max(image.width,image.height))))
            let wallpaper=try ImageExport.encode(reduced,type:"public.jpeg",quality:0.9)
            commit { $0.backdrop.wallpaper=wallpaper; $0.backdrop.fill = .wallpaper }
        } catch { message=error.localizedDescription }
    }
}

extension RGBA {
    init(_ color: NSColor) {
        let c=color.usingColorSpace(.sRGB) ?? color
        self.init(red:c.redComponent,green:c.greenComponent,blue:c.blueComponent,alpha:c.alphaComponent)
    }
    var nsColor: NSColor { NSColor(srgbRed:red,green:green,blue:blue,alpha:alpha) }
}
