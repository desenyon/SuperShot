import AppKit
import SwiftUI
import Capture
import DesignSystem
import Settings
import Export
import Document
import Render
import Editor
import Recognition
import Library
import Observation
import UniformTypeIdentifiers

@MainActor final class CaptureController {
    enum Mode { case screen, area, window, previous, text, code, scrolling }
    private let service = CaptureService()
    private let overlay = SelectionOverlay()
    private let recognizer = RecognitionService()
    private let history = HistoryStore()
    private let scrolling = ScrollController()
    private var libraryWindow: HistoryController?
    private var results: [NSWindow] = []
    private let settings: SettingsStore
    private let permission: ScreenPermission
    private let requestPermission: () -> Void
    private var busy = false
    private var countdownTask: Task<Void,Never>?
    private var countdownPanel: NSPanel?
    private let clipboard = ClipboardWriter()
    private var choosingSave = false
    private var pendingSaves: [UUID:Task<Void,Never>] = [:]
    private var previous: (display: CGDirectDisplayID, selection: CGRect)?
    private var thumbnailScreen: NSScreen?
    private var thumbnails: [NSPanel] = []
    private var editors: [EditorWindowController] = []
    let pins = PinController()
    var hasVisibleSurface: Bool { busy || scrolling.isRunning || pins.hasVisiblePins || libraryWindow?.window?.isVisible == true || results.contains(where:{$0.isVisible}) || thumbnails.contains(where: { $0.isVisible }) || editors.contains(where: { $0.window?.isVisible == true }) }
    private(set) var last: CapturedImage?
    init(settings: SettingsStore, permission: ScreenPermission, requestPermission: @escaping () -> Void) {
        self.settings=settings; self.permission=permission; self.requestPermission=requestPermission
    }
    func prepare() { if permission.state == .authorized { Task { try? await service.prepare() } } }
    func capture(_ mode: Mode) {
        permission.refresh()
        guard permission.state == .authorized else { requestPermission(); return }
        guard !busy, !scrolling.isRunning, let screen = NSScreen.underPointer else { return }
        if mode == .previous, previous == nil { showError("Select an area first. SuperShot will remember it for next time."); return }
        busy=true
        let start = ContinuousClock.now
        Task { [self] in
            do {
                let display = mode == .previous ? previous!.display : screen.displayID
                async let candidates: [CaptureWindow]? = (mode == .window || mode == .area) ? service.windows() : nil
                let image = try await service.screen(id:display,cursor:settings.preferences.includeCursor,hideDesktopIcons:settings.preferences.hideDesktopIcons)
                switch mode {
                case .screen:
                    defer { busy = false }; await finish(image, mode: .screen)
                case .previous:
                    defer { busy = false }
                    if let selection = previous?.selection, let crop = image.image.cropping(to:selection) {
                        await finish(CapturedImage(image:crop,scale:image.scale,source:"Area"),mode: .area)
                    }
                case .area, .window, .text, .code, .scrolling:
                    let choices = try await candidates
                    overlay.show(screen:screen,capture:image,windows:mode == .window ? choices : nil,snappingWindows:choices ?? [],showsActions:mode == .area,captureOnRelease:mode == .area && settings.preferences.captureOnRelease) { [weak self] rect, id, action in
                        guard let self else { return }
                        guard id != nil || rect != nil else { self.busy = false; return }
                        // Keep the capture session busy until its asynchronous outputs finish.
                        // An older completion must never clear the flag for a newer overlay.
                        Task { [self] in
                            defer {self.busy=false}
                            do {
                                if let id { await self.finish(try await self.service.window(id:id,cursor:self.settings.preferences.includeCursor,keepShadow:self.settings.preferences.keepWindowShadow),mode: .window) }
                                else if let rect {
                                    let pixels = SelectionGeometry.pixels(selection:rect,viewSize:screen.frame.size,imageSize:CGSize(width:image.image.width,height:image.image.height))
                                    if let crop = image.image.cropping(to:pixels) {
                                        self.previous=(screen.displayID,pixels)
                                        let capture = CapturedImage(image:crop,scale:image.scale,source:"Area")
                                        if mode == .text || mode == .code { await self.recognizeCapture(capture, codes: mode == .code) }
                                        else if mode == .scrolling {
                                            self.scrolling.start(first:capture,display:screen.displayID,area:pixels,service:self.service) { [weak self] capture in Task { await self?.finish(capture,mode: .scrolling) } }
                                        } else {
                                            switch action {
                                            case .capture: await self.finish(capture,mode: .area)
                                            case .copy: await self.finish(capture,mode: .area,override:[.copy])
                                            case .save: await self.finish(capture,mode: .area,override:[.save])
                                            case .edit: await self.finish(capture,mode: .area,override:[.editor])
                                            case .pin: await self.finish(capture,mode: .area,override:[.pin])
                                            case .text: await self.recognizeCapture(capture, codes:false)
                                            }
                                        }
                                    }
                                }
                            } catch { self.showError(error.localizedDescription) }
                        }
                    }
                    log("overlay", duration:start.duration(to:.now))
                }
            } catch { busy=false; showError(error.localizedDescription) }
        }
    }
    func captureAllDisplays() {
        permission.refresh()
        guard permission.state == .authorized else { requestPermission(); return }
        guard !busy,!scrolling.isRunning else {return};busy=true
        let displays=NSScreen.screens.map(\.displayID),preferences=settings.preferences
        Task {
            defer {busy=false}
            do {for display in displays {let image=try await service.screen(id:display,cursor:preferences.includeCursor,hideDesktopIcons:preferences.hideDesktopIcons);await finish(image,mode: .screen)}}
            catch {showError(error.localizedDescription)}
        }
    }
    func captureTimed(seconds: Int) {
        guard !busy,!scrolling.isRunning else{return};busy=true
        let state=CountdownState(seconds:seconds)
        let countdownSize=CGSize(width:220,height:236)
        let panel=NSPanel(contentRect:CGRect(origin:.zero,size:countdownSize),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.level = .floating;panel.isOpaque=false;panel.backgroundColor = .clear;panel.isReleasedWhenClosed=false
        state.cancel={ [weak self] in self?.countdownTask?.cancel();self?.countdownTask=nil;self?.countdownPanel?.close();self?.countdownPanel=nil;self?.busy=false }
        let host=NSHostingView(rootView:CountdownView(state:state));host.sizingOptions=[];panel.contentView=host;panel.setContentSize(countdownSize);panel.center();panel.orderFrontRegardless();countdownPanel=panel
        countdownTask=Task { [weak self] in
            do {
                while state.seconds>0 {try await Task.sleep(for:.seconds(1));state.seconds-=1}
                guard let self,!Task.isCancelled else{return}
                self.countdownPanel?.close();self.countdownPanel=nil;self.countdownTask=nil;self.busy=false;self.capture(.area)
            } catch {}
        }
    }
    func applyPreset(_ backdrop:Backdrop) {
        if let editor=editors.first(where:{$0.window?.isKeyWindow == true}) {editor.model.commit{$0.backdrop=backdrop};return}
        guard let last else{return}
        Task {do {var doc=try await makeDocument(last);doc.backdrop=backdrop;openDocument(doc)} catch {showError(error.localizedDescription)}}
    }
    private func pinImage(_ image: CGImage) { pins.pin(image, preferences: settings.preferences.floating) }
    func pinClipboard() {
        guard let image=NSImage(pasteboard:.general)?.cgImage(forProposedRect:nil,context:nil,hints:nil) else {showError("Copy an image before pinning it.");return}
        pins.pin(image, preferences: settings.preferences.floating)
    }
    func openLast() { if let last { preview(last) } else { showError("Take a screenshot first to open your last capture.") } }
    /// `override` replaces the configured after-capture actions for this one capture.
    private func finish(_ capture: CapturedImage, mode: CaptureActionMode, override: Set<AfterCapture>? = nil) async {
        last=capture
        let actions = settings.preferences.actions(for: mode, override: override)
        // Reserve the copy before backdrop rendering can suspend this task.
        let copyRequest = actions.contains(.copy) ? clipboard.begin() : nil
        if settings.preferences.historyEnabled {
            let retention = settings.preferences.retentionDays
            let token = UUID()
            pendingSaves[token] = Task {
                defer { pendingSaves[token] = nil }
                do {
                    let doc = try await makeDocument(capture)
                    try await history.save(doc,retentionDays:retention,onlyIfMissing:true)
                    // Saving the original must finish on quit; optional indexing need not delay it.
                    Task {
                        do {
                            let result = try await recognizer.recognize(capture.image)
                            try await history.updateText(result.transcript,id:doc.id)
                        } catch { FileHandle.standardError.write(Data("History recognition: \(error.localizedDescription)\n".utf8)) }
                    }
                } catch { FileHandle.standardError.write(Data("History: \(error.localizedDescription)\n".utf8)) }
            }
        }
        settings.preferences.onboardingCompleted = true
        if settings.preferences.captureSound { NSSound(named:"Tink")?.play() }
        let styled: CapturedImage
        var project: CaptureDocument?
        do {
            if settings.preferences.automaticBackdrop || settings.preferences.saveSidecar {
                let doc = try await makeDocument(capture); project = doc
                if settings.preferences.automaticBackdrop {
                    let rendered = try await Task.detached(priority:.userInitiated) { try DocumentRenderer.render(doc) }.value
                    styled = CapturedImage(image:rendered,scale:capture.scale,source:capture.source)
                } else { styled = capture }
            } else { styled = capture }
        } catch { showError(error.localizedDescription); return }
        if actions.contains(.editor) { preview(capture) }
        if actions.contains(.pin) { pins.pin(styled.image, preferences: settings.preferences.floating) }
        if actions.contains(.thumbnail) { thumbnail(capture,display:styled.image) }
        if let copyRequest { await copy(styled, request: copyRequest) }
        if actions.contains(.save) { await save(styled, choose:false, project:project) }
    }
    func copy(_ capture: CapturedImage, request: ClipboardWriter.Request? = nil) async {
        let request = request ?? clipboard.begin()
        do {
            let preferences=settings.preferences
            let type=preferences.clipboardFormat
            let data = try await Task.detached(priority:.userInitiated) {
                let image=try ImageExport.transformed(capture.image,factor:preferences.oneX ? 1/capture.scale:1,sRGB:preferences.convertToSRGB)
                return try ImageExport.encode(image,type:type,quality:preferences.quality)
            }.value
            try clipboard.write(data, type: type, for: request)
        } catch { showError(error.localizedDescription) }
    }
    func save(_ capture: CapturedImage, choose: Bool, type: String? = nil, project: CaptureDocument? = nil) async {
        let preferences=settings.preferences
        let type=type ?? preferences.fileFormat
        let format = ImageExport.formats.first { $0.id == type }
        let filename = ImageExport.templateFilename(preferences.filenameTemplate,date:capture.date,app:capture.source,window:capture.source,counter:preferences.filenameCounter,width:capture.image.width,height:capture.image.height,extensionName:format?.extensionName ?? "png")
        settings.preferences.filenameCounter = preferences.filenameCounter >= Int.max-1 ? 1:preferences.filenameCounter+1
        let destination: URL
        if choose {
            guard !choosingSave else{return};choosingSave=true
            defer{choosingSave=false}
            let panel = NSSavePanel(); panel.nameFieldStringValue=filename
            panel.allowedContentTypes=[UTType(type) ?? .png]
            NSApp.activate(ignoringOtherApps:true)
            guard panel.runModal() == .OK, let url=panel.url else { return }
            destination=url
        } else {
            var folder=URL(fileURLWithPath:preferences.saveFolder)
            if preferences.subfolders == "date" {let formatter=DateFormatter();formatter.dateFormat="yyyy-MM-dd";folder.appendPathComponent(formatter.string(from:capture.date))}
            if preferences.subfolders == "app" {folder.appendPathComponent(ImageExport.templateFilename("{app}",date:capture.date,app:capture.source,window:"",counter:0,width:0,height:0,extensionName:"").trimmingCharacters(in:CharacterSet(charactersIn:".")))}
            destination=folder.appendingPathComponent(filename)
        }
        do {
            try await Task.detached(priority:.userInitiated) {
                let image=try ImageExport.transformed(capture.image,factor:preferences.oneX ? 1/capture.scale:1,sRGB:preferences.convertToSRGB)
                let data=try ImageExport.encode(image,type:type,quality:preferences.quality)
                if preferences.saveSidecar,let project {
                    let projectData=try ProjectFile.encode(project)
                    if choose {
                        try data.write(to:destination,options:.atomic)
                        let sidecar=destination.deletingPathExtension().appendingPathExtension("supershot")
                        if let existing=try? Data(contentsOf:sidecar),let old=try? ProjectFile.decode(existing),old.id == project.id {try projectData.write(to:sidecar,options:.atomic)}
                        else {_ = try ImageExport.writeUnique(projectData,to:sidecar)}
                    } else {_ = try ImageExport.writePair(image:data,project:projectData,to:destination)}
                } else if choose {try data.write(to:destination,options:.atomic)}
                else {_ = try ImageExport.writeUnique(data,to:destination)}
            }.value
        } catch { showError(error.localizedDescription) }
    }
    private func thumbnail(_ capture: CapturedImage, display: CGImage? = nil) {
        let presented = display.map{CapturedImage(image:$0,scale:capture.scale,source:capture.source)} ?? capture
        guard let screen=NSScreen.underPointer else { return }
        let preferences = settings.preferences.floating
        let size = CGSize(width: preferences.thumbnailWidth, height: preferences.thumbnailWidth * DS.thumbnailSize.height / DS.thumbnailSize.width)
        let capacity = max(1, min(3, Int((screen.visibleFrame.height - DS.xl * 2) / (size.height + DS.md))))
        while thumbnails.count >= capacity { thumbnails.removeFirst().close() }
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.isReleasedWhenClosed = false; panel.hasShadow = false
        let dismiss: () -> Void = { [weak self, weak panel] in
            panel?.close(); self?.thumbnails.removeAll { $0 === panel }; self?.layoutThumbnails()
        }
        let view = ThumbnailView(capture: presented, open: { [weak self] in self?.preview(capture) },
                                 copy: { [weak self] in Task { await self?.copy(presented) } },
                                 save: { [weak self] in Task { await self?.save(presented, choose: true, project: try? await self?.makeDocument(capture)) } },
                                 pin: { [weak self] in self?.pinImage(presented.image); dismiss() }, dismiss: dismiss)
        let hosting = NSHostingView(rootView: view); hosting.sizingOptions = []; panel.contentView = hosting
        panel.setContentSize(size); thumbnailScreen = screen
        thumbnails.append(panel); layoutThumbnails(); panel.orderFrontRegardless()
        if preferences.thumbnailSeconds > 0 {
            Task { @MainActor [weak panel] in
                var remaining = preferences.thumbnailSeconds
                while remaining > 0 {
                    try? await Task.sleep(for: .seconds(1))
                    guard let panel, panel.isVisible else { return }
                    if !panel.frame.contains(NSEvent.mouseLocation) { remaining -= 1 }
                }
                dismiss()
            }
        }
    }
    private func layoutThumbnails() {
        guard let screen = thumbnailScreen else { return }
        let corner = settings.preferences.floating.thumbnailCorner
        var offset = DS.xl
        for panel in thumbnails.reversed() {
            let size = panel.frame.size
            panel.setFrameOrigin(CGPoint(x: corner.isRight ? screen.visibleFrame.maxX - size.width - DS.xl : screen.visibleFrame.minX + DS.xl,
                                         y: corner.isTop ? screen.visibleFrame.maxY - size.height - offset : screen.visibleFrame.minY + offset))
            offset += size.height + DS.md
        }
    }
    func preview(_ capture: CapturedImage) {
        if let editor=editors.first(where:{$0.model.document.id == capture.id}) {editor.present();return}
        Task {
            do {
                if let saved=try? await history.document(capture.id) {openDocument(saved)}
                else {openDocument(try await makeDocument(capture))}
            } catch { showError(error.localizedDescription) }
        }
    }
    private func makeDocument(_ capture: CapturedImage) async throws -> CaptureDocument {
        let data = try await Task.detached(priority: .userInitiated) { try ImageExport.encode(capture.image) }.value
        var document = CaptureDocument(original:data,width:capture.image.width,height:capture.image.height,scale:capture.scale,source:capture.source,date:capture.date)
        document.id = capture.id
        document.preserveColorProfile = !settings.preferences.convertToSRGB
        if settings.preferences.automaticBackdrop {document.backdrop=settings.preferences.defaultBackdrop}
        return document
    }
    func showHistory() {
        if libraryWindow == nil { libraryWindow = HistoryController(store:history,open:{ [weak self] in self?.openDocument($0) }) }
        libraryWindow?.present()
    }
    private func recognizeCapture(_ capture: CapturedImage, codes: Bool) async {
        do {
            let result = try await recognizer.recognize(capture.image,accurate:true)
            if !codes {
                guard !result.transcript.isEmpty else { showError("No readable text was found in that area."); return }
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(result.transcript,forType:.string)
            } else {
                guard !result.codes.isEmpty else { showError("No QR code or barcode was found in that area."); return }
                let window = NSWindow(contentRect:CGRect(origin:.zero,size:DS.illustrationSize),styleMask:[.titled,.closable],backing:.buffered,defer:false)
                window.title = "Recognized codes";window.isReleasedWhenClosed=false
                let host = NSHostingView(rootView:CodeResultsView(codes:result.codes));host.sizingOptions=[];window.contentView=host;window.setContentSize(DS.illustrationSize)
                results.removeAll{!$0.isVisible};results.append(window);window.center();NSApp.activate(ignoringOtherApps:true);window.makeKeyAndOrderFront(nil)
            }
        } catch { showError(error.localizedDescription) }
    }
    func openDocument(_ document: CaptureDocument) {
        if let existing=editors.first(where:{$0.model.document.id == document.id}) {existing.present();return}
        let editor = EditorWindowController(document: document)
        editor.model.format = settings.preferences.fileFormat
        editor.model.toolShortcuts = settings.preferences.toolShortcuts
        editor.model.savedPresets = settings.preferences.backdropPresets
        editor.model.savePresetAction = { [weak self,weak model=editor.model] name,backdrop in
            guard let self else{return}
            self.settings.preferences.backdropPresets.append(BackdropPreset(name:name,backdrop:backdrop))
            model?.savedPresets=self.settings.preferences.backdropPresets
        }
        editor.model.saveBackdropAction = { [weak self] backdrop in self?.settings.preferences.defaultBackdrop = backdrop }
        editor.model.autosaveAction = { [weak self, weak model = editor.model] document in
            guard let self, self.settings.preferences.historyEnabled else { return }
            let retention = self.settings.preferences.retentionDays
            let token=UUID()
            self.pendingSaves[token]=Task { [weak self] in
                guard let self else{return}
                defer{self.pendingSaves[token]=nil}
                do {try await self.history.save(document,retentionDays:retention)}
                catch {model?.message="Edits could not be saved to history: \(error.localizedDescription)"}
            }
        }
        editor.model.copyAction = { [weak self] image in Task { await self?.copy(CapturedImage(image: image, scale: document.scale, source: document.source)) } }
        editor.model.saveAction = { [weak self] image, type, snapshot in Task { await self?.save(CapturedImage(image: image, scale: snapshot.scale, source: snapshot.source), choose: true, type: type, project: snapshot) } }
        editor.model.pinAction = { [weak self] image in self?.pinImage(image) }
        // Flush closed sessions before releasing them; the current document always wins over stale disk snapshots.
        for closed in editors where closed.window?.isVisible != true {closed.model.flushAutosave()}
        editors.removeAll { $0.window?.isVisible != true }; editors.append(editor); editor.present()
    }
    func openFile(_ url: URL) {
        Task {
            do {
                let doc = try await Task.detached(priority: .userInitiated) {
                    let data = try Data(contentsOf: url)
                    if url.pathExtension.lowercased() == "supershot" { return try ProjectFile.decode(data) }
                    guard let image = DocumentRenderer.decode(data) else { throw DocumentRenderer.Error.invalidImage }
                    return CaptureDocument(original: data, width: image.width, height: image.height, source: url.deletingPathExtension().lastPathComponent)
                }.value
                openDocument(doc)
            } catch { showError(error.localizedDescription) }
        }
    }
    func openImage() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image, UTType(filenameExtension: "supershot") ?? .data]
        if panel.runModal() == .OK, let url = panel.url { openFile(url) }
    }
    func openClipboard() {
        guard let image = NSImage(pasteboard: .general)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { showError("Copy an image first, then open it from the clipboard."); return }
        preview(CapturedImage(image: image, scale: 1, source: "Clipboard"))
    }
    func flushEdits() async {
        editors.forEach{$0.model.flushAutosave()}
        while !pendingSaves.isEmpty {
            let pending=Array(pendingSaves.values)
            for task in pending {await task.value}
        }
    }
    private func showError(_ message: String) {
        let alert=NSAlert(); alert.messageText="SuperShot"; alert.informativeText=message
        NSApp.activate(ignoringOtherApps:true); alert.runModal()
    }
    private func log(_ phase: String, duration: Duration) {
        FileHandle.standardError.write(Data("SuperShot \(phase) latency: \(duration)\n".utf8))
        #if DEBUG
        let milliseconds = Double(duration.components.seconds)*1000 + Double(duration.components.attoseconds)/1e15
        let key="SuperShot.diagnostics.\(phase)Milliseconds"
        var samples=UserDefaults.standard.array(forKey:key) as? [Double] ?? []
        samples.append(milliseconds)
        UserDefaults.standard.set(Array(samples.suffix(20)),forKey:key)
        #endif
    }
}

struct ThumbnailView: View {
    @Environment(\.colorScheme) private var scheme
    @LocalState private var hovering = false
    let capture: CapturedImage
    let open: () -> Void
    let copy: () -> Void
    let save: () -> Void
    let pin: () -> Void
    let dismiss: () -> Void
    var body: some View {
        ZStack {
            DS.panel(scheme)
            Image(nsImage: NSImage(cgImage: capture.image, size: .zero)).resizable().scaledToFit().padding(6)
                .onDrag { NSItemProvider(object: NSImage(cgImage: capture.image, size: .zero)) }
            if hovering {
                Color.black.opacity(0.38)
                Button(action: open) { Label("Edit", systemImage: "pencil.tip.crop.circle") }.buttonStyle(PrimaryButtonStyle())
                    .accessibilityLabel("Open in editor")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.14)))
        .overlay(alignment: .topLeading) {
            if hovering { chip { IconButton("xmark", label: "Dismiss", size: 24, action: dismiss) } }
        }
        .overlay(alignment: .bottom) {
            if hovering {
                chip {
                    IconButton("doc.on.doc", label: "Copy", size: 26, action: copy)
                    IconButton("square.and.arrow.down", label: "Save as…", size: 26, action: save)
                    IconButton("pin", label: "Pin to screen", size: 26, action: pin)
                }
            } else {
                HStack { Tag("\(capture.image.width) × \(capture.image.height)").background(DS.panel(scheme).opacity(0.9), in: Capsule()); Spacer() }.padding(DS.sm)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: open)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
        .padding(DS.sm)
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
    }
    private func chip<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 2) { content() }.padding(3).modifier(GlassSurface(radius: 11)).padding(DS.sm)
    }
}

struct CodeResultsView: View {
    let codes: [CodeRegion]
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.md) {
                HStack(spacing: DS.sm) {
                    Image(systemName: "qrcode.viewfinder").font(.system(size: 18, weight: .medium)).foregroundStyle(DS.actionInk(scheme))
                    Text(codes.count == 1 ? "Code found" : "\(codes.count) codes found").font(DS.title)
                }
                ForEach(codes) { code in
                    Card {
                        Text(code.payload).font(DS.mono).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: DS.sm) {
                            Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code.payload, forType: .string) }.buttonStyle(QuietButtonStyle())
                            if let url = URL(string: code.payload), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                                Button("Open link") { NSWorkspace.shared.open(url) }.buttonStyle(PrimaryButtonStyle())
                            }
                        }.padding(.top, DS.md)
                    }
                }
            }.padding(DS.xl)
        }.background(DS.background(scheme))
    }
}

@MainActor @Observable final class CountdownState {
    var seconds: Int
    let total: Int
    var cancel: () -> Void = {}
    init(seconds: Int) { self.seconds = seconds; total = seconds }
}
struct CountdownView: View {
    @Bindable var state: CountdownState
    var body: some View {
        VStack(spacing: DS.md) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.12), lineWidth: 5)
                Circle().trim(from: 0, to: CGFloat(state.seconds) / CGFloat(max(1, state.total)))
                    .stroke(DS.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: state.seconds)
                Text("\(state.seconds)").font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit().contentTransition(.numericText())
            }.frame(width: 104, height: 104)
            Text("Set up your screen").font(DS.caption).foregroundStyle(.secondary)
            Button("Cancel", action: state.cancel).buttonStyle(QuietButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).modifier(GlassSurface(radius: 28)).padding(DS.sm)
    }
}
