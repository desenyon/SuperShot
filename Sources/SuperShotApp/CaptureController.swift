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
import AI

@MainActor final class CaptureController {
    enum Mode { case screen, area, disposable, window, previous, text, code, scrolling }
    private let service = CaptureService()
    private let overlay = SelectionOverlay()
    private let recognizer = RecognitionService()
    private let history = HistoryStore()
    private lazy var linkedExports: LinkedExports = LinkedExports(folder: history.folder)
    private let organizer = CaptureOrganizer()
    private let scrolling = ScrollController()
    private var libraryWindow: HistoryController?
    private var results: [NSWindow] = []
    private let settings: SettingsStore
    private let permission: ScreenPermission
    private let requestPermission: () -> Void
    private let librarySettings: (() -> Void)?
    private let openRecordings: (() -> Void)?
    private var busy = false
    private var countdownTask: Task<Void,Never>?
    private var countdownPanel: NSPanel?
    private let clipboard = ClipboardWriter()
    private var choosingSave = false
    private var pendingSaves: [UUID:Task<Void,Never>] = [:]
    private var disposableIDs: Set<UUID> = []
    private var keepTasks: [UUID: Task<Bool, Never>] = [:]
    private var exportRevision: UInt64 = 0
    private var previous: (display: CGDirectDisplayID, selection: CGRect)?
    private var thumbnailScreen: NSScreen?
    private var thumbnails: [ThumbnailPanel] = []
    private let recent = RecentCaptures()
    private var recentWindow: NSWindow?
    private var floatingAsk: AskPanelController?
    private let askSelection = ThumbnailAskSelection()
    private var requestedAsk: UUID?
    private var appliedAssistant: AssistantPreferences?
    private var editors: [EditorWindowController] = []
    private let reviewLinks = ReviewLinksController()
    let pins = PinController()
    var hasVisibleSurface: Bool { busy || scrolling.isRunning || pins.hasVisiblePins || libraryWindow?.window?.isVisible == true || recentWindow?.isVisible == true || results.contains(where:{$0.isVisible}) || thumbnails.contains(where: { $0.isVisible }) || editors.contains(where: { $0.window?.isVisible == true }) }
    private(set) var last: CapturedImage?
    init(settings: SettingsStore, permission: ScreenPermission, requestPermission: @escaping () -> Void,
         librarySettings: (() -> Void)? = nil, openRecordings: (() -> Void)? = nil) {
        self.settings=settings; self.permission=permission; self.requestPermission=requestPermission
        self.librarySettings = librarySettings
        self.openRecordings = openRecordings
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
                async let candidates: [CaptureWindow]? = (mode == .window || mode == .area || mode == .disposable) ? service.windows() : nil
                let image = try await service.screen(id:display,cursor:settings.preferences.includeCursor,hideDesktopIcons:settings.preferences.hideDesktopIcons)
                switch mode {
                case .screen:
                    defer { busy = false }; await finish(image, mode: .screen)
                case .previous:
                    defer { busy = false }
                    if let selection = previous?.selection, let crop = image.image.cropping(to:selection) {
                        await finish(CapturedImage(image:crop,scale:image.scale,source:"Area"),mode: .area)
                    }
                case .area, .disposable, .window, .text, .code, .scrolling:
                    let choices = try await candidates
                    let area = mode == .area || mode == .disposable
                    let tint = settings.preferences.selectionTint.map { NSColor(srgbRed: $0.red, green: $0.green, blue: $0.blue, alpha: 1) }
                    overlay.show(screen:screen,capture:image,windows:mode == .window ? choices : nil,snappingWindows:choices ?? [],showsActions:area,captureOnRelease:area && settings.preferences.captureOnRelease,
                                 overlayActions: settings.preferences.customization.overlayActions.compactMap(OverlayAction.init(rawValue:)).filter { $0 != .ask || settings.preferences.assistant.isEnabled },
                                 showsLabels: settings.preferences.customization.overlayLabels, selectionTint: tint,
                                 selectionTintOpacity: settings.preferences.selectionTintOpacity) { [weak self] rect, id, action in
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
                                        if area && action != .text { self.previous = (screen.displayID, pixels) }
                                        let capture = CapturedImage(image:crop,scale:image.scale,source:"Area")
                                        if mode == .text || mode == .code { await self.recognizeCapture(capture, codes: mode == .code) }
                                        else if mode == .scrolling {
                                            self.scrolling.start(first:capture,display:screen.displayID,area:pixels,service:self.service) { [weak self] capture in Task { await self?.finish(capture,mode: .scrolling) } }
                                        } else {
                                            await self.finishArea(capture, action: action, disposable: mode == .disposable)
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
        permission.refresh()
        guard permission.state == .authorized else { requestPermission(); return }
        guard !busy,!scrolling.isRunning else{return};busy=true
        let state=CountdownState(seconds:seconds)
        let countdownSize = CountdownView.size
        let panel = CountdownPanel(contentRect: CGRect(origin: .zero, size: countdownSize),
                                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating;panel.isOpaque=false;panel.backgroundColor = .clear;panel.isReleasedWhenClosed=false
        state.cancel={ [weak self] in self?.countdownTask?.cancel();self?.countdownTask=nil;self?.countdownPanel?.close();self?.countdownPanel=nil;self?.busy=false }
        panel.cancel = state.cancel
        let host=NSHostingView(rootView:CountdownView(state:state));host.sizingOptions=[];panel.contentView=host;panel.setContentSize(countdownSize);panel.center();panel.makeKeyAndOrderFront(nil);countdownPanel=panel
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
        Task {
            do {
                let model = openDocument(try await latestDocument(for: last))
                model.commit { $0.backdrop = backdrop }
            } catch { showError(error.localizedDescription) }
        }
    }
    private func pinImage(_ image: CGImage) { pins.pin(image, preferences: settings.preferences.floating) }
    func pinClipboard() {
        guard let image=NSImage(pasteboard:.general)?.cgImage(forProposedRect:nil,context:nil,hints:nil) else {showError("Copy an image before pinning it.");return}
        pins.pin(image, preferences: settings.preferences.floating)
    }
    func openLast() { if let last { preview(last) } else { showError("Take a screenshot first to open your last capture.") } }
    private func finishArea(_ capture: CapturedImage, action: OverlayAction, disposable: Bool) async {
        if action == .text { await recognizeCapture(capture, codes: false); return }
        let override: Set<AfterCapture>? = switch action {
        case .capture: disposable ? [.thumbnail] : nil
        case .copy: [.copy]
        case .save: [.save]
        case .edit: [.editor]
        case .pin: [.pin]
        case .ask: [.thumbnail]
        case .text: nil
        }
        await finish(capture, mode: .area, override: override, openAsk: action == .ask, disposable: disposable)
    }

    func acceptWebpage(_ capture: CapturedImage) async { await finish(capture, mode: .webpage) }

    /// `override` replaces the configured after-capture actions for this one capture.
    private func finish(_ capture: CapturedImage, mode: CaptureActionMode, override: Set<AfterCapture>? = nil, openAsk: Bool = false, disposable: Bool = false) async {
        last=capture
        recent.insert(capture, disposable: disposable)
        var actions = settings.preferences.actions(for: mode, override: override)
        if disposable {
            disposableIDs.insert(capture.id)
            actions.insert(.thumbnail)
        }
        // Reserve the copy before backdrop rendering can suspend this task.
        let copyRequest = actions.contains(.copy) ? clipboard.begin() : nil
        if settings.preferences.historyEnabled && !disposable {
            let retention = settings.preferences.retentionDays
            let token = UUID()
            pendingSaves[token] = Task {
                defer { pendingSaves[token] = nil }
                do {
                    let doc = try await makeDocument(capture)
                    try await history.save(doc,retentionDays:retention,onlyIfMissing:true)
                    indexCapture(capture)
                } catch { FileHandle.standardError.write(Data("History: \(error.localizedDescription)\n".utf8)) }
            }
        }
        settings.preferences.onboardingCompleted = true
        if settings.preferences.captureSound { NSSound(named: settings.preferences.captureSoundName ?? "Tink")?.play() }
        let styled: CapturedImage
        var project: CaptureDocument?
        do {
            if settings.preferences.automaticBackdrop || settings.preferences.saveSidecar ||
                (actions.contains(.save) && settings.preferences.historyEnabled && settings.preferences.keepExportUpdated && !disposable) {
                let doc = try await makeDocument(capture); project = doc
                if settings.preferences.automaticBackdrop {
                    let rendered = try await Task.detached(priority:.userInitiated) { try DocumentRenderer.render(doc) }.value
                    styled = capture.replacingImage(rendered)
                } else { styled = capture }
            } else { styled = capture }
        } catch { showError(error.localizedDescription); return }
        if actions.contains(.editor) { preview(capture) }
        if actions.contains(.pin) { pins.pin(styled.image, preferences: settings.preferences.floating) }
        if actions.contains(.thumbnail) { thumbnail(capture, display: styled.image, openAsk: openAsk) }
        if let copyRequest { await copy(styled, request: copyRequest) }
        if actions.contains(.save) { await save(styled, choose:false, project:project) }
    }

    private func indexCapture(_ capture: CapturedImage) {
        // Saving the original must finish on quit. Optional indexing can be interrupted.
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await recognizer.recognize(capture.image)
                try await history.updateText(result.transcript, id: capture.id)
                if settings.preferences.organizeCapturesLocally {
                    let suggestions = await organizer.suggest(image: capture.image, recognition: result, source: capture.source,
                                                               useAppleIntelligence: settings.preferences.useAppleIntelligenceForOrganization)
                    try await history.updateSuggestions(HistorySuggestions(title: suggestions.title, tags: suggestions.tags,
                                                                          summary: suggestions.summary), id: capture.id)
                }
                libraryWindow?.refreshIfVisible()
            } catch {
                FileHandle.standardError.write(Data("History recognition: \(error.localizedDescription)\n".utf8))
            }
        }
    }

    private func keepDisposable(_ capture: CapturedImage) async -> Bool {
        if let task = keepTasks[capture.id] { return await task.value }
        guard settings.preferences.historyEnabled, disposableIDs.contains(capture.id) else { return false }
        let task = Task { [self] in
            defer { keepTasks.removeValue(forKey: capture.id) }
            return await persistDisposable(capture)
        }
        keepTasks[capture.id] = task
        return await task.value
    }
    private func persistDisposable(_ capture: CapturedImage) async -> Bool {
        do {
            let model = editors.first(where: { $0.model.document.id == capture.id })?.model
                ?? floatingAsk?.editor.flatMap { $0.document.id == capture.id ? $0 : nil }
            let document: CaptureDocument
            if let model { document = model.document } else { document = try await makeDocument(capture) }
            try await history.save(document, retentionDays: settings.preferences.retentionDays, onlyIfMissing: true)
            disposableIDs.remove(capture.id)
            recent.markKept(capture.id)
            if let model, model.document != document { model.autosaveAction?(model.document) }
            if let messages = model?.ask?.messages, !messages.isEmpty { storeConversation(messages, id: capture.id) }
            indexCapture(capture)
            return true
        } catch {
            showError(error.localizedDescription)
            return false
        }
    }
    @discardableResult func copy(_ capture: CapturedImage, request: ClipboardWriter.Request? = nil, reportError: Bool = true) async -> EditorWriteResult {
        let request = request ?? clipboard.begin()
        do {
            let preferences=settings.preferences
            let type=preferences.clipboardFormat
            let data = try await Task.detached(priority:.userInitiated) {
                let image=try ImageExport.transformed(capture.image,factor:preferences.oneX ? 1/capture.scale:1,sRGB:preferences.convertToSRGB)
                return try ImageExport.encode(image,type:type,quality:preferences.quality)
            }.value
            return try clipboard.write(data, type: type, for: request) ? .written : .failed("The clipboard changed before the copy finished.")
        } catch {
            if reportError { showError(error.localizedDescription) }
            return .failed(error.localizedDescription)
        }
    }
    @discardableResult func save(_ capture: CapturedImage, choose: Bool, type: String? = nil, project: CaptureDocument? = nil, reportError: Bool = true) async -> EditorWriteResult {
        let preferences=settings.preferences
        let type=type ?? preferences.fileFormat
        let format = ImageExport.formats.first { $0.id == type }
        let app = project?.sourceApplication ?? capture.applicationName ?? capture.source
        let title = project?.sourceWindow ?? capture.windowTitle ?? ""
        let date = project?.date ?? capture.date
        let filename = ImageExport.templateFilename(preferences.filenameTemplate, date: date, app: app, window: title,
                                                    counter: preferences.filenameCounter, width: capture.image.width,
                                                    height: capture.image.height, extensionName: format?.extensionName ?? "png")
        settings.preferences.filenameCounter = preferences.filenameCounter >= Int.max-1 ? 1:preferences.filenameCounter+1
        let destination: URL
        if choose {
            guard !choosingSave else{return .cancelled};choosingSave=true
            defer{choosingSave=false}
            let panel = NSSavePanel(); panel.nameFieldStringValue=filename
            panel.allowedContentTypes=[UTType(type) ?? .png]
            NSApp.activate(ignoringOtherApps:true)
            guard panel.runModal() == .OK, let url=panel.url else { return .cancelled }
            destination=url
        } else {
            var folder=URL(fileURLWithPath:preferences.saveFolder)
            if preferences.subfolders == "date" {let formatter=DateFormatter();formatter.dateFormat="yyyy-MM-dd";folder.appendPathComponent(formatter.string(from:date))}
            if preferences.subfolders == "app" {folder.appendPathComponent(ImageExport.templateFilename("{app}",date:date,app:app,window:"",counter:0,width:0,height:0,extensionName:"").trimmingCharacters(in:CharacterSet(charactersIn:".")))}
            destination=folder.appendingPathComponent(filename)
        }
        do {
            let canLink = preferences.historyEnabled && preferences.keepExportUpdated &&
                !choose && project != nil && !disposableIDs.contains(project?.id ?? capture.id)
            let format = LinkedExports.Format(type: type, scaleFactor: preferences.oneX ? 1 / capture.scale : 1,
                                              sRGB: preferences.convertToSRGB, quality: preferences.quality)
            let linked = try await Task.detached(priority: .userInitiated) { () -> (URL, Data)? in
                let image = try ImageExport.transformed(capture.image, factor: format.scaleFactor, sRGB: format.sRGB)
                let data = try ImageExport.encode(image, type: format.type, quality: format.quality)
                let written: URL
                if preferences.saveSidecar,let project {
                    let projectData=try ProjectFile.encode(project)
                    if choose {
                        try data.write(to:destination,options:.atomic)
                        let sidecar=destination.deletingPathExtension().appendingPathExtension("supershot")
                        if let existing=try? Data(contentsOf:sidecar),let old=try? ProjectFile.decode(existing),old.id == project.id {try projectData.write(to:sidecar,options:.atomic)}
                        else {_ = try ImageExport.writeUnique(projectData,to:sidecar)}
                        written = destination
                    } else {
                        written = try ImageExport.writePair(image: data, project: projectData, to: destination)
                    }
                } else if choose {
                    try data.write(to: destination, options: .atomic)
                    written = destination
                } else { written = try ImageExport.writeUnique(data, to: destination) }
                return canLink ? (written, data) : nil
            }.value
            if let (url, bytes) = linked, let project {
                do {
                    try await linkedExports.link(id: project.id, url: url, bytes: bytes, format: format)
                    if let latest = editors.first(where: { $0.model.document.id == project.id })?.model.document, latest != project {
                        exportRevision &+= 1
                        _ = try await linkedExports.refresh(latest, revision: exportRevision)
                    }
                }
                catch { showError("Saved \(url.lastPathComponent), but could not link it to future edits.") }
            }
            return .written
        } catch {
            if reportError { showError(error.localizedDescription) }
            return .failed(error.localizedDescription)
        }
    }
    private func thumbnail(_ capture: CapturedImage, display: CGImage? = nil, openAsk: Bool = false) {
        let presented = display.map { capture.replacingImage($0) } ?? capture
        guard let screen=NSScreen.underPointer else { return }
        let preferences = settings.preferences.floating
        let size = CGSize(width: preferences.thumbnailWidth, height: preferences.thumbnailWidth * DS.thumbnailSize.height / DS.thumbnailSize.width + DS.xxl)
        let capacity = max(1, min(3, Int((screen.visibleFrame.height - DS.xl * 2) / (size.height + DS.md))))
        while thumbnails.count >= capacity, let oldest = thumbnails.first(where: { $0 !== floatingAsk?.anchor }) {
            dismissThumbnail(oldest)
        }
        let panel = ThumbnailPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.isReleasedWhenClosed = false; panel.hasShadow = false
        let dismiss: () -> Void = { [weak self, weak panel] in
            if let panel { self?.dismissThumbnail(panel) }
        }
        panel.swipeAway = dismiss
        let showAsk: () -> Void = { [weak self, weak panel] in
            if let panel { self?.toggleAsk(for: capture, anchor: panel) }
        }
        let view = ThumbnailView(capture: presented, settings: settings, selection: askSelection, captureID: capture.id, ask: showAsk,
                                 open: { [weak self] in self?.preview(capture) },
                                 copy: { [weak self] in Task { await self?.copy(presented) } },
                                 save: { [weak self] in Task { await self?.saveThumbnail(capture, fallback: presented) } },
                                 pin: { [weak self] in Task {
                                     if await self?.pinThumbnail(capture, fallback: presented) == true { dismiss() }
                                 } }, dismiss: dismiss,
                                 copyWithResult: { [weak self] in
                                     await self?.copyLatest(capture, clipboardFallback: presented) ?? false
                                 },
                                 keep: disposableIDs.contains(capture.id) && settings.preferences.historyEnabled
                                     ? { [weak self] in await self?.keepDisposable(capture) ?? false }
                                     : nil,
                                 dragProvider: { [weak self] in self?.thumbnailDragProvider(capture, fallback: presented) ?? NSItemProvider() })
        let hosting = NSHostingView(rootView: view); hosting.sizingOptions = []; hosting.wantsLayer = true; panel.contentView = hosting
        panel.setContentSize(size); thumbnailScreen = screen
        thumbnails.append(panel); layoutThumbnails(); panel.orderFrontRegardless()
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        DS.Motion.present(panel, reduceMotion: reduced)
        if !reduced {
            let x = panel.onRight ? DS.xxl : -DS.xxl
            let from = CATransform3DTranslate(CATransform3DMakeScale(0.94, 0.94, 1), x, 0, 0)
            hosting.layer?.add(DS.Motion.caSpring("transform", from: NSValue(caTransform3D: from),
                                                  to: NSValue(caTransform3D: CATransform3DIdentity), reduceMotion: false), forKey: "present")
        }
        if openAsk { showAsk() }
        if preferences.thumbnailSeconds > 0 {
            Task { @MainActor [weak self, weak panel] in
                var remaining = preferences.thumbnailSeconds
                while remaining > 0 {
                    try? await Task.sleep(for: .seconds(1))
                    guard let panel, panel.isVisible else { return }
                    if self?.floatingAsk?.anchor !== panel, self?.requestedAsk != capture.id, !panel.frame.contains(NSEvent.mouseLocation) { remaining -= 1 }
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
            let origin = CGPoint(x: corner.isRight ? screen.visibleFrame.maxX - size.width - DS.xl : screen.visibleFrame.minX + DS.xl,
                                         y: corner.isTop ? screen.visibleFrame.maxY - size.height - offset : screen.visibleFrame.minY + offset)
            panel.destination = CGRect(origin: origin, size: size)
            panel.onRight = corner.isRight
            panel.move(to: origin, animated: panel.isVisible)
            offset += size.height + DS.md
        }
        floatingAsk?.follow(animated: true)
    }
    private func dismissThumbnail(_ panel: ThumbnailPanel) {
        guard thumbnails.contains(panel) else { return }
        if floatingAsk?.anchor === panel { closeAsk() }
        thumbnails.removeAll { $0 === panel }
        DS.Motion.dismiss(panel, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) { panel.close() }
        layoutThumbnails()
    }

    private func closeAsk(handoff: Bool = false) {
        requestedAsk = nil; askSelection.id = nil
        guard let panel = floatingAsk else { return }
        floatingAsk = nil
        if !handoff, !editors.contains(where: { $0.model === panel.editor && $0.window?.isVisible == true }) { panel.editor?.ask?.end() }
        DS.Motion.dismiss(panel, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) { panel.close() }
    }

    private func toggleAsk(for capture: CapturedImage, anchor: ThumbnailPanel) {
        guard settings.preferences.assistant.isEnabled else { return }
        if askSelection.id == capture.id || requestedAsk == capture.id { closeAsk(); return }
        requestedAsk = capture.id
        Task { [self] in
            do {
                let source: EditorModel
                if let current = editors.first(where: { $0.model.document.id == capture.id && $0.window?.isVisible == true }) {
                    source = current.model
                } else {
                    let document = try await latestDocument(for: capture)
                    source = EditorModel(document: document)
                    source.askOptions = AssistantWiring.options(settings.preferences.assistant)
                    source.assistantFactory = AssistantWiring.factory
                    await keepConversations(for: source)
                }
                guard requestedAsk == capture.id, thumbnails.contains(anchor), settings.preferences.assistant.isEnabled else { return }
                requestedAsk = nil
                let panel = floatingAsk ?? AskPanelController()
                if let previous = panel.editor, previous !== source, !editors.contains(where: { $0.model === previous && $0.window?.isVisible == true }) { previous.ask?.end() }
                floatingAsk = panel; askSelection.id = capture.id
                panel.onDismiss = { [weak self] in self?.closeAsk() }
                panel.present(editor: source, beside: anchor) { [weak self] in
                    guard let self else { return source }
                    let target = openDocument(source.document, conversation: source.ask)
                    closeAsk(handoff: true)
                    return target
                }
            } catch {
                guard requestedAsk == capture.id else { return }
                requestedAsk = nil; showError(error.localizedDescription)
            }
        }
    }

    func updateAssistantPreferences() {
        let prefs = settings.preferences.assistant
        guard prefs != appliedAssistant else { return }
        let old = appliedAssistant
        appliedAssistant = prefs
        let options = AssistantWiring.options(prefs)
        if options == nil { closeAsk() }
        let models = editors.map(\.model) + [floatingAsk?.editor].compactMap { $0 }
        for model in models {
            model.askOptions = options
            if let options {
                model.ask?.updateOptions(options, changedProvider: old?.provider != prefs.provider)
            } else {
                if model.inspector == "ask" { model.inspector = "" }
                model.ask?.end(); model.ask = nil
            }
        }
    }

    func preview(_ capture: CapturedImage) {
        if let editor=editors.first(where:{$0.model.document.id == capture.id}) {editor.present();return}
        Task {
            do {
                openDocument(try await latestDocument(for: capture))
            } catch { showError(error.localizedDescription) }
        }
    }
    private func latestDocument(for capture: CapturedImage) async throws -> CaptureDocument {
        if let document = try await retainedDocument(for: capture.id) { return document }
        return try await makeDocument(capture)
    }

    private func retainedDocument(for id: UUID) async throws -> CaptureDocument? {
        if let model = editors.first(where: { $0.model.document.id == id })?.model { return model.document }
        if await history.wasRemoved(id) {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "This capture was removed from the Library."])
        }
        return try await history.storedDocument(id)
    }

    private func copyLatest(_ capture: CapturedImage, clipboardFallback: CapturedImage? = nil) async -> Bool {
        let request = clipboard.begin()
        do {
            let output: CapturedImage
            if let document = try await retainedDocument(for: capture.id) {
                output = try await renderCapture(document)
            } else { output = clipboardFallback ?? capture }
            return await copy(output, request: request) == .written
        } catch {
            showError(error.localizedDescription)
            return false
        }
    }
    private func renderCapture(_ document: CaptureDocument) async throws -> CapturedImage {
        let image = try await Task.detached(priority: .userInitiated) { try DocumentRenderer.render(document) }.value
        return CapturedImage(image: image, scale: document.scale, source: document.source, id: document.id,
                             date: document.date, applicationName: document.sourceApplication, windowTitle: document.sourceWindow)
    }

    private func saveThumbnail(_ capture: CapturedImage, fallback: CapturedImage) async {
        do {
            if let document = try await retainedDocument(for: capture.id) {
                _ = await save(try await renderCapture(document), choose: true, project: document)
            } else {
                _ = await save(fallback, choose: true, project: try await makeDocument(capture))
            }
        } catch { showError(error.localizedDescription) }
    }

    private func pinThumbnail(_ capture: CapturedImage, fallback: CapturedImage) async -> Bool {
        do {
            if let document = try await retainedDocument(for: capture.id) {
                pinImage(try await renderCapture(document).image)
            } else { pinImage(fallback.image) }
            return true
        } catch {
            showError(error.localizedDescription)
            return false
        }
    }

    private func thumbnailDragProvider(_ capture: CapturedImage, fallback: CapturedImage) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = "SuperShot"
        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { [weak self] completion in
            let progress = Progress(totalUnitCount: 1)
            let rendering = Task { @MainActor in
                do {
                    guard let self else { throw CancellationError() }
                    let document = try await self.retainedDocument(for: capture.id)
                    let data = try await Task.detached(priority: .userInitiated) {
                        let image = try document.map { try DocumentRenderer.render($0) } ?? fallback.image
                        return try ImageExport.encode(image)
                    }.value
                    try Task.checkCancellation()
                    progress.completedUnitCount = 1
                    completion(data, nil)
                } catch { completion(nil, error) }
            }
            progress.cancellationHandler = { rendering.cancel() }
            return progress
        }
        return provider
    }
    private func makeDocument(_ capture: CapturedImage) async throws -> CaptureDocument {
        let data = try await Task.detached(priority: .userInitiated) { try ImageExport.encode(capture.image) }.value
        var document = CaptureDocument(original:data,width:capture.image.width,height:capture.image.height,scale:capture.scale,source:capture.source,date:capture.date)
        document.id = capture.id
        document.sourceApplication = capture.applicationName
        document.sourceWindow = capture.windowTitle
        document.preserveColorProfile = !settings.preferences.convertToSRGB
        if settings.preferences.automaticBackdrop {document.backdrop=settings.preferences.defaultBackdrop}
        return document
    }
    func showHistory() {
        if libraryWindow == nil {
            libraryWindow = HistoryController(store: history, open: { [weak self] in _ = self?.openDocument($0) },
                                               capture: { [weak self] in self?.capture(.area) }, openSettings: librarySettings,
                                               openRecordings: openRecordings,
                                               historyEnabled: { [weak self] in self?.settings.preferences.historyEnabled == true },
                                               copyEntry: { [weak self] id in
                                                   guard let self else { return }
                                                   let request = clipboard.begin()
                                                   guard let document = try await retainedDocument(for: id) else {
                                                       throw CocoaError(.fileReadNoSuchFile)
                                                   }
                                                   let output = try await renderCapture(document)
                                                   if case .failed(let message) = await copy(output, request: request, reportError: false) {
                                                       throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: message])
                                                   }
                                               })
        }
        libraryWindow?.present()
    }
    func showReviewLinks() { reviewLinks.showManagement() }
    func shareRecording(_ url: URL, title: String, parent: NSWindow?) { reviewLinks.show(file: url, title: title, parent: parent) }
    func showRecent() {
        if recentWindow == nil {
            let scene = RecentCapturesView(recent: recent, open: { [weak self] in self?.preview($0) },
                                           copy: { [weak self] in
                                               await self?.copyLatest($0) ?? false
                                           }, keep: { [weak self] in await self?.keepDisposable($0) ?? false },
                                           library: { [weak self] in self?.showHistory() },
                                           canKeep: { [weak self] in self?.settings.preferences.historyEnabled == true })
            let window = NSWindow(contentViewController: NSHostingController(rootView: scene))
            window.title = "Recent Captures"
            window.styleMask = [.titled, .closable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(RecentCapturesView.size)
            window.center()
            recentWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        recentWindow?.makeKeyAndOrderFront(nil)
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
    /// Restores the conversation kept with this capture and saves new replies, when History and the setting allow.
    private func keepConversations(for model: EditorModel) async {
        let id = model.document.id
        model.configureAsk = { [weak self] ask in
            ask.onTranscript = { messages in self?.storeConversation(messages, id: id) }
        }
        guard settings.preferences.historyEnabled, settings.preferences.assistant.keepConversations,
              let stored = try? await history.conversation(id), !stored.isEmpty, model.ask == nil else { return }
        model.restoredAskMessages = stored.map { AskMessage($0.role == "user" ? .user : .assistant, $0.text, attachments: $0.attachments) }
    }
    private func storeConversation(_ messages: [AskMessage], id: UUID) {
        guard settings.preferences.historyEnabled, settings.preferences.assistant.keepConversations else { return }
        let stored = messages.map { StoredMessage(role: $0.role == .user ? "user" : "assistant", text: $0.text, attachments: $0.attachments) }
        Task { [history] in try? await history.saveConversation(stored, id: id) }
    }
    /// Deletes every kept conversation. Called when the user turns the setting off.
    func forgetConversations() { Task { [history] in try? await history.removeAllConversations() } }

    @discardableResult func openDocument(_ document: CaptureDocument, conversation: AskModel? = nil) -> EditorModel {
        if let existing = editors.first(where: { $0.model.document.id == document.id }) {
            if let conversation { existing.model.ask = conversation; existing.model.openAsk() }
            existing.present(); return existing.model
        }
        let editor = EditorWindowController(document: document) { [settings] in
            EditorChrome(tools: settings.preferences.customization.editorTools)
        }
        editor.model.askOptions = AssistantWiring.options(settings.preferences.assistant)
        editor.model.assistantFactory = AssistantWiring.factory
        if let conversation { editor.model.ask = conversation; editor.model.openAsk() }
        else { Task { await keepConversations(for: editor.model) } }
        NotificationCenter.default.addObserver(self, selector: #selector(editorWillClose(_:)), name: NSWindow.willCloseNotification, object: editor.window)
        editor.model.format = settings.preferences.fileFormat
        editor.model.toolShortcuts = settings.preferences.toolShortcuts
        editor.model.savedPresets = settings.preferences.backdropPresets
        editor.model.defaultBackdrop = settings.preferences.automaticBackdrop ? settings.preferences.defaultBackdrop : nil
        editor.model.fileExportScale = { [settings] in settings.preferences.oneX ? 1 / document.scale : 1 }
        editor.model.shareLinkAction = { [weak self, weak window = editor.window] image, title in
            self?.reviewLinks.show(image: image, title: title, parent: window)
        }
        editor.model.savePresetAction = { [weak self,weak model=editor.model] name,backdrop in
            guard let self else{return}
            self.settings.preferences.backdropPresets.append(BackdropPreset(name:name,backdrop:backdrop))
            model?.savedPresets=self.settings.preferences.backdropPresets
            self.updatePresetsInEditors()
        }
        editor.model.saveBackdropAction = { [weak self, weak model = editor.model] backdrop in
            guard let self else { return }
            settings.preferences.defaultBackdrop = backdrop
            settings.preferences.automaticBackdrop = true
            model?.defaultBackdrop = backdrop
        }
        editor.model.importPresetAction = { [weak self] in self?.importBackdropPreset() }
        editor.model.exportPresetAction = { [weak self] in self?.exportBackdropPreset($0) }
        editor.model.updatePresetAction = { [weak self] preset, backdrop in
            guard let self, let index = settings.preferences.backdropPresets.firstIndex(where: { $0.id == preset.id }) else { return }
            if settings.preferences.defaultBackdrop == preset.backdrop { settings.preferences.defaultBackdrop = backdrop }
            settings.preferences.backdropPresets[index].backdrop = backdrop
            updatePresetsInEditors()
        }
        editor.model.autosaveAction = { [weak self, weak model = editor.model] document in
            guard let self, !self.disposableIDs.contains(document.id) else { return }
            let saveHistory = self.settings.preferences.historyEnabled
            let updateExport = saveHistory && self.settings.preferences.keepExportUpdated
            guard saveHistory || updateExport else { return }
            let retention = self.settings.preferences.retentionDays
            self.exportRevision &+= 1
            let revision = self.exportRevision
            let token=UUID()
            self.pendingSaves[token]=Task { [weak self] in
                guard let self else{return}
                defer{self.pendingSaves[token]=nil}
                if saveHistory {
                    do {
                        try await self.history.save(document, retentionDays: retention, revision: revision)
                        self.libraryWindow?.refreshIfVisible()
                    }
                    catch { model?.message = "Edits could not be saved to history: \(error.localizedDescription)" }
                }
                if updateExport {
                    do {
                        if try await self.linkedExports.refresh(document, revision: revision) == .detached {
                            model?.message = "The exported file changed outside SuperShot. Future edits stay in this project."
                        }
                    } catch { model?.message = "Could not update the linked export: \(error.localizedDescription)" }
                }
            }
        }
        editor.model.copyAction = { [weak self] image in
            await self?.copy(CapturedImage(image: image, scale: document.scale, source: document.source), reportError: false) ?? .cancelled
        }
        editor.model.saveAction = { [weak self] image, type, snapshot in
            await self?.save(CapturedImage(image: image, scale: snapshot.scale, source: snapshot.source),
                             choose: true, type: type, project: snapshot, reportError: false) ?? .cancelled
        }
        editor.model.pinAction = { [weak self] image in self?.pinImage(image) }
        // Flush closed sessions before releasing them; the current document always wins over stale disk snapshots.
        for closed in editors where closed.window?.isVisible != true {closed.model.flushAutosave()}
        editors.removeAll { $0.window?.isVisible != true }; editors.append(editor); editor.present(); return editor.model
    }

    private func updatePresetsInEditors() {
        for editor in editors {
            editor.model.savedPresets = settings.preferences.backdropPresets
            editor.model.defaultBackdrop = settings.preferences.automaticBackdrop ? settings.preferences.defaultBackdrop : nil
        }
    }

    private func importBackdropPreset() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                let preset = try await Task.detached(priority: .userInitiated) {
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard (1...64 * 1024 * 1024).contains(size) else { throw CocoaError(.fileReadCorruptFile) }
                    return try BackdropPresetTransfer.decode(Data(contentsOf: url))
                }.value
                settings.preferences.backdropPresets.append(BackdropPreset(name: preset.name, backdrop: preset.backdrop))
                updatePresetsInEditors()
            } catch { showError("Couldn’t import the preset. \(error.localizedDescription)") }
        }
    }

    private func exportBackdropPreset(_ preset: BackdropPreset) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = preset.name + ".supershot-preset.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try BackdropPresetTransfer.encode(preset).write(to: url, options: .atomic)
                }.value
            } catch { showError("Couldn’t export the preset. \(error.localizedDescription)") }
        }
    }
    @objc private func editorWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let editor = editors.first(where: { $0.window === window }), floatingAsk?.editor !== editor.model else { return }
        editor.model.ask?.end()
        editor.model.ask = nil
        if editor.model.inspector == "ask" { editor.model.inspector = "" }
    }

    func openFile(_ url: URL) {
        Task {
            do {
                var doc = try await Task.detached(priority: .userInitiated) {
                    let data = try Data(contentsOf: url)
                    if url.pathExtension.lowercased() == "supershot" { return try ProjectFile.decode(data) }
                    guard let image = DocumentRenderer.decode(data) else { throw DocumentRenderer.Error.invalidImage }
                    return CaptureDocument(original: data, width: image.width, height: image.height, source: url.deletingPathExtension().lastPathComponent)
                }.value
                if url.pathExtension.lowercased() == "supershot" {
                    let canonical = try await history.storedDocument(doc.id)
                    let linkedWithoutHistory = canonical == nil ? try await linkedExports.contains(doc.id) : false
                    if canonical.map({ $0 != doc }) == true || linkedWithoutHistory { doc.id = UUID() }
                }
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
        floatingAsk?.editor?.ask?.end()
        editors.forEach { $0.model.ask?.end() }
        editors.forEach{$0.model.flushAutosave()}
        for task in Array(keepTasks.values) { _ = await task.value }
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

@MainActor @Observable final class ThumbnailAskSelection {
    var id: UUID?
}

/// A hover button on the thumbnail's glass bar: a soft wash on hover, accent fill while its panel is open.
private struct ThumbnailGlassButton: View {
    let icon: String
    let label: String
    let active: Bool
    var title: String? = nil
    let perform: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @LocalState private var hovering = false
    var body: some View {
        Button(action: perform) {
            HStack(spacing: DS.xs) {
                Icon(icon, weight: active || hovering ? .fill : .regular, size: DS.iconSize)
                if let title { Text(title).font(DS.caption.weight(.medium)) }
            }
                .foregroundStyle(active ? DS.onAccent : Color.primary.opacity(hovering ? 1 : 0.85))
                .padding(.horizontal, DS.xs)
                .frame(minWidth: DS.Ask.send, minHeight: DS.Ask.send)
                .background {
                    if active { RoundedRectangle(cornerRadius: DS.controlRadius, style: .continuous).fill(DS.accent) }
                    else if hovering { RoundedRectangle(cornerRadius: DS.controlRadius, style: .continuous).fill(DS.hover(scheme)) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle()).help(label).accessibilityLabel(label)
        .onHover { over in withAnimation(DS.Motion.hover(reduced)) { hovering = over } }
    }
}

struct ThumbnailView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @LocalState private var hovering = false
    @LocalState private var copied = false
    @LocalState private var feedback: Task<Void, Never>?
    @LocalState private var kept = false
    @LocalState private var keeping = false
    let capture: CapturedImage
    var settings: SettingsStore?
    var selection: ThumbnailAskSelection?
    var captureID: UUID?
    var ask: () -> Void = {}
    let open: () -> Void
    let copy: () -> Void
    let save: () -> Void
    let pin: () -> Void
    let dismiss: () -> Void
    var copyWithResult: (() async -> Bool)?
    var keep: (() async -> Bool)?
    var dragProvider: (() -> NSItemProvider)?

    private var active: Bool { captureID != nil && selection?.id == captureID }
    private var actions: [String] {
        var seen = Set<String>()
        return (settings?.preferences.customization.thumbnailActions ?? CustomizationPreferences.defaultThumbnailActions)
            .filter { seen.insert($0).inserted && ($0 != "ask" || settings?.preferences.assistant.isEnabled != false) }
    }
    var body: some View {
        VStack(spacing: DS.xs) {
            ZStack {
                DS.panel(scheme)
                Image(decorative: capture.image, scale: 1).resizable().scaledToFit()
                    .onDrag { dragProvider?() ?? NSItemProvider(object: NSImage(cgImage: capture.image, size: .zero)) }
            }
            .contentShape(Rectangle()).onTapGesture(perform: open)
            .accessibilityLabel("Open capture in editor").accessibilityAddTraits(.isButton)
            .accessibilityAction { open() }
            .clipShape(RoundedRectangle(cornerRadius: DS.smallRadius))
            .overlay(RoundedRectangle(cornerRadius: DS.smallRadius)
                .strokeBorder(active ? DS.accent : DS.hairline(scheme), lineWidth: active ? DS.stroke * 2 : DS.stroke)
                .allowsHitTesting(false))

            ViewThatFits(in: .horizontal) {
                shelf(showLabels: true).fixedSize(horizontal: true, vertical: false)
                shelf(showLabels: false).fixedSize(horizontal: true, vertical: false)
                compactShelf
            }
            .padding(DS.xs)
            .frame(maxWidth: .infinity, minHeight: DS.xl + DS.sm)
            .modifier(GlassSurface(radius: DS.smallRadius, interactive: true,
                                   backing: DS.panel(scheme).opacity(0.45)))
        }
        .onHover { hovering = $0 }
        .animation(DS.Motion.panel(reduced), value: hovering || active)
        .padding(DS.sm).shadow(color: DS.black.opacity(DS.shadowOpacity), radius: DS.md, y: DS.xs)
        .onDisappear { feedback?.cancel() }
    }

    private func shelf(showLabels: Bool) -> some View {
        let isActive = hovering || active || copied
        return HStack(spacing: 0) {
            if !isActive && (keep == nil || kept) {
                Text(verbatim: "\(capture.image.width) × \(capture.image.height)")
                    .font(DS.mono).foregroundStyle(.secondary).lineLimit(1).padding(.leading, DS.sm)
                Spacer(minLength: DS.xs)
            }
            if let keep, !kept {
                keepButton(keep, showLabel: showLabels)
            }
            ForEach(isActive ? actions : actions.filter { ["edit", "ask", "delete"].contains($0) }, id: \.self) { id in
                let item = button(id)
                let title = showLabels
                    ? (id == "edit" ? "Edit" : id == "ask" ? "Ask" : id == "copy" && copied ? "Copied" : nil)
                    : nil
                ThumbnailGlassButton(icon: item.icon, label: item.label, active: active && id == "ask",
                                     title: title, perform: item.perform)
            }
        }
    }

    private var compactShelf: some View {
        let pinned = Set(["edit", "ask", "delete"])
        return HStack(spacing: DS.xs) {
            if let keep, !kept { keepButton(keep, showLabel: false) }
            ForEach(actions.filter { pinned.contains($0) }, id: \.self) { id in
                let item = button(id)
                ThumbnailGlassButton(icon: item.icon, label: item.label, active: active && id == "ask", perform: item.perform)
            }
            let overflow = actions.filter { !pinned.contains($0) }
            if !overflow.isEmpty {
                Menu {
                    ForEach(overflow, id: \.self) { id in
                        let item = button(id)
                        Button(item.label, action: item.perform)
                    }
                } label: {
                    Icon("dots-three", size: DS.iconSize).frame(width: DS.Ask.send, height: DS.Ask.send)
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).accessibilityLabel("More capture actions")
            }
        }
    }

    private func keepButton(_ keep: @escaping () async -> Bool, showLabel: Bool) -> some View {
        ThumbnailGlassButton(icon: "tray-arrow-down", label: "Keep in Library", active: false,
                             title: showLabel ? "Keep" : nil) {
            guard !keeping else { return }
            keeping = true
            Task { kept = await keep(); keeping = false }
        }
        .disabled(keeping)
    }

    private func copyCapture() {
        guard let copyWithResult else { copy(); return }
        feedback?.cancel()
        feedback = Task {
            guard await copyWithResult(), !Task.isCancelled else { return }
            withAnimation(DS.Motion.gentle(reduced)) { copied = true }
            try? await Task.sleep(for: .seconds(1.3))
            guard !Task.isCancelled else { return }
            withAnimation(DS.Motion.gentle(reduced)) { copied = false }
        }
    }
    private func button(_ id: String) -> (icon: String, label: String, perform: () -> Void) {
        switch id {
        case "copy": (copied ? "check" : "copy", copied ? "Copied" : "Copy", copyCapture)
        case "save": ("download-simple", "Save as…", save)
        case "pin": ("push-pin", "Pin to screen", pin)
        case "ask": ("chat-circle-dots", "Ask about this capture", ask)
        case "edit": ("pencil-simple", "Open in editor", open)
        default: ("x", "Dismiss thumbnail", dismiss)
        }
    }
}

struct CodeResultsView: View {
    let codes: [CodeRegion]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.md) {
                WorkspaceHeader(title: codes.count == 1 ? "Code found" : "\(codes.count) codes found", icon: "qr-code")
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
        }.background { WorkspaceBackground() }
    }
}

@MainActor @Observable final class CountdownState {
    var seconds: Int
    let total: Int
    var cancel: () -> Void = {}
    init(seconds: Int) { self.seconds = seconds; total = seconds }
}
struct CountdownView: View {
    static let size = CGSize(width: 196, height: 84)
    @Bindable var state: CountdownState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: DS.md) {
            ZStack {
                Circle().stroke(Color.primary.opacity(DS.outlineOpacity), lineWidth: DS.xs)
                Circle().trim(from: 0, to: CGFloat(state.seconds) / CGFloat(max(1, state.total)))
                    .stroke(DS.accent, style: StrokeStyle(lineWidth: DS.xs, lineCap: .round)).rotationEffect(.degrees(-90))
                    .animation(DS.Motion.tick(reduceMotion), value: state.seconds)
                Text("\(state.seconds)").font(DS.title).monospacedDigit()
                    .contentTransition(reduceMotion ? .opacity : .numericText(countsDown: true))
                    .animation(DS.Motion.arrive(reduceMotion), value: state.seconds)
            }.frame(width: DS.xxl, height: DS.xxl)
            VStack(alignment: .leading, spacing: DS.xs) {
                Text("Area capture").font(DS.emphasis)
                Button("Esc to cancel", action: state.cancel).buttonStyle(.plain)
                    .font(DS.caption).foregroundStyle(.secondary)
            }
        }
        .padding(DS.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(GlassSurface(radius: DS.md)).padding(DS.sm)
    }
}

private final class CountdownPanel: NSPanel {
    var cancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { cancel?() }
}
