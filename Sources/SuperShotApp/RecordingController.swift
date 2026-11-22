import AppKit
import AVFoundation
import Capture
import DesignSystem
import Settings
import SwiftUI

struct RecordingChoice: Identifiable {
    let id: UInt32
    let name: String
    var frame: CGRect? = nil
    var pixelSize: CGSize? = nil

    var detail: String? {
        guard let size = pixelSize ?? frame?.size else { return nil }
        let units = pixelSize == nil ? "pt" : "px"
        return "\(Int(size.width.rounded()).formatted()) × \(Int(size.height.rounded()).formatted()) \(units)"
    }
}

struct RecordingInputChoice: Identifiable {
    let id: String
    let name: String
}

@MainActor @Observable final class RecordingSetup {
    enum Mode: String, CaseIterable {
        case display = "Display", window = "Window", area = "Area"

        var icon: String {
            switch self {
            case .display: "monitor"
            case .window: "app-window"
            case .area: "selection"
            }
        }
    }
    enum Phase: Equatable { case ready, starting, recording, finishing }

    var mode: Mode = .display
    var phase: Phase = .ready
    var options = RecordingOptions()
    var displays: [RecordingChoice] = []
    var windows: [RecordingChoice] = []
    var microphones: [RecordingInputChoice] = []
    var displayID: UInt32?
    var windowID: UInt32?
    var area: CGRect?
    var cameraLayout: RecordingCameraLayout = .bottomRight
    var delay = 0
    var countdown: Int?
    var loadingWindows = false
    var loadingPreview = false
    var preview: CGImage?
    var error: String?
    var startedAt: Date?

    var source: RecordingSource? {
        switch mode {
        case .display: displayID.map(RecordingSource.display)
        case .window: windowID.map(RecordingSource.window)
        case .area:
            if let displayID, let area { .area(displayID, area) } else { nil }
        }
    }

    var selectedName: String {
        switch mode {
        case .display, .area: displays.first(where: { $0.id == displayID })?.name ?? mode.rawValue
        case .window: windows.first(where: { $0.id == windowID })?.name ?? mode.rawValue
        }
    }
}

@MainActor final class RecordingController: NSObject, NSWindowDelegate {
    var shareReviewLink: ((URL, String, NSWindow?) -> Void)?
    var canStopRecording: Bool { setup.phase == .recording }
    private let permission: ScreenPermission
    private let openPrivacy: () -> Void
    private let assistantSettings: SettingsStore?
    private let archive = RecordingArchive()
    private let setup = RecordingSetup()
    private var session: ScreenRecordingSession?
    private var setupWindow: NSWindow?
    private var setupWindowHasPermission: Bool?
    private var controlWindow: NSPanel?
    private var recordingsWindow: NSWindow?
    private var editors: [URL: RecordingEditorController] = [:]
    private var startTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    private var windowListTask: Task<Void, Never>?
    private let sourceCapture = CaptureService()
    private let sourceOverlay = SelectionOverlay()
    private var areaTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var previewRequest: UUID?
    private var choosingArea = false
    private var camera: RecordingCamera?
    private var clickMonitor: Any?
    private var automaticZooms: [RecordingZoom] = []
    private var terminating = false

    init(permission: ScreenPermission, openPrivacy: @escaping () -> Void, assistantSettings: SettingsStore? = nil) {
        self.permission = permission
        self.openPrivacy = openPrivacy
        self.assistantSettings = assistantSettings
    }

    func present() {
        guard !terminating, !choosingArea else { return }
        if setup.phase == .recording || setup.phase == .finishing {
            controlWindow?.orderFrontRegardless()
            return
        }
        if setup.phase == .starting {
            NSApp.activate(ignoringOtherApps: true)
            setupWindow?.makeKeyAndOrderFront(nil)
            return
        }
        permission.refresh()
        updateDisplays()
        updateMicrophones()
        if setup.mode == .window { updateWindows() }
        if setupWindow == nil {
            let view = RecordingSetupView(model: setup, permission: permission, loadWindows: { [weak self] in self?.updateWindows() },
                                          openPrivacy: openPrivacy, record: { [weak self] in self?.start() },
                                          chooseArea: { [weak self] in self?.chooseArea() },
                                          previewSource: { [weak self] in self?.previewSource() },
                                          resetPreview: { [weak self] in self?.resetPreview() },
                                          cancelStart: { [weak self] in self?.startTask?.cancel() },
                                          refreshDisplays: { [weak self] in self?.updateDisplays() },
                                          permissionChanged: { [weak self] in self?.updateSetupWindowSize() })
            let ideal = permission.state == .authorized ? RecordingSetupView.preferredSize : RecordingSetupView.permissionSize
            let window = Self.makeWindow(title: "Record Screen", ideal: ideal, resizable: true, view: view)
            window.delegate = self
            setupWindow = window
        }
        updateSetupWindowSize()
        NSApp.activate(ignoringOtherApps: true)
        setupWindow?.makeKeyAndOrderFront(nil)
    }

    private func updateSetupWindowSize() {
        guard let window = setupWindow else { return }
        let authorized = permission.state == .authorized
        guard setupWindowHasPermission != authorized else { return }
        let wasConfigured = setupWindowHasPermission != nil
        setupWindowHasPermission = authorized
        let preferred = authorized ? RecordingSetupView.preferredSize : RecordingSetupView.permissionSize
        let available = window.screen?.visibleFrame.size ?? NSScreen.main?.visibleFrame.size ?? preferred
        let size = DS.fittingWindowSize(preferred: preferred, available: available)
        let minimum = authorized ? RecordingSetupView.minimumSize : RecordingSetupView.permissionSize
        window.contentMinSize = CGSize(width: min(minimum.width, size.width), height: min(minimum.height, size.height))
        if wasConfigured { window.setContentSize(size) }
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === setupWindow else { return }
        startTask?.cancel()
        resetPreview()
    }

    func stop() {
        guard stopTask == nil, let session, setup.phase == .recording else { return }
        removeClickMonitor()
        setup.phase = .finishing
        stopTask = Task { [weak self] in
            guard let self else { return }
            async let webcam = finishCamera()
            var showSetup = false
            defer {
                stopTask = nil
                setup.startedAt = nil
                setup.phase = .ready
                self.session = nil
                camera = nil
                hideControls()
                if showSetup && !terminating { present() }
            }
            let url: URL
            let info: RecordingMediaInfo
            var issues: [String] = []
            do {
                let finished = try await session.finish()
                info = try await RecordingMedia.inspect(finished)
                url = finished
            } catch {
                // A disconnected source can still leave a playable file.
                let partial = session.outputURL
                guard let recovered = try? await RecordingMedia.inspect(partial) else {
                    try? FileManager.default.removeItem(at: partial)
                    if case .success(let clip) = await webcam { clip?.discard() }
                    report(error)
                    showSetup = true
                    return
                }
                info = recovered
                url = partial
                issues.append("SuperShot recovered the video recorded before the source stopped.")
            }
            do {
                let saved = try archive.commit(url, at: setup.startedAt ?? .now)
                var hasCamera = false
                do {
                    if let clip = try await webcam.get() {
                        defer { clip.discard() }
                        if let startedAt = session.startedAtHostTime {
                            _ = try await clip.persist(for: saved, screenStartedAt: startedAt)
                            hasCamera = true
                        }
                    }
                } catch { issues.append(error.localizedDescription) }
                do {
                    if hasCamera || !automaticZooms.isEmpty {
                        var edits = RecordingEdits(trim: info.range)
                        if hasCamera { edits.cameraLayout = setup.cameraLayout }
                        edits.zooms = automaticZooms.compactMap { zoom in
                            zoom.range.intersection(info.range).map { RecordingZoom(range: $0, center: zoom.center) }
                        }
                        try JSONEncoder().encode(edits).write(to: RecordingMedia.editsURL(for: saved), options: .atomic)
                    }
                } catch { issues.append("Recording edits could not be saved. \(error.localizedDescription)") }
                let issue = issues.isEmpty ? nil : "The screen recording was saved. \(issues.joined(separator: " "))"
                if let issue { setup.error = issue }
                if !terminating { openEditor(saved, message: issue) }
            } catch {
                report(error)
                if case .success(let clip) = await webcam { clip?.discard() }
                if !terminating { openEditor(url, message: "Couldn’t add this recording to Recordings. Export a copy to keep it.") }
            }
        }
    }

    func finishBeforeTermination() async {
        terminating = true
        resetPreview()
        areaTask?.cancel()
        sourceOverlay.dismiss()
        startTask?.cancel()
        await startTask?.value
        stop()
        await stopTask?.value
    }

    func presentLibrary() {
        let view = RecordingLibraryView(archive: archive, open: { [weak self] in self?.openEditor($0) },
                                        record: { [weak self] in self?.present() })
        let window = Self.makeWindow(title: "Recordings", ideal: CGSize(width: 560, height: 430), view: view)
        recordingsWindow?.close()
        recordingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func start() {
        guard !terminating, setup.phase == .ready, let source = setup.source else { return }
        permission.refresh()
        guard permission.state == .authorized else { return }
        setup.error = nil
        setup.phase = .starting
        resetPreview()
        let options = setup.options
        let delay = setup.delay
        startTask = Task { [weak self] in
            guard let self else { return }
            defer { setup.countdown = nil; startTask = nil }
            var reserved: URL?
            do {
                if options.microphone {
                    let allowed = await AVCaptureDevice.requestAccess(for: .audio)
                    try Task.checkCancellation()
                    guard allowed else { throw RecordingFailure.microphoneAccess }
                    if let mic = options.microphoneDeviceID, !Self.microphones.contains(where: { $0.id == mic }) {
                        updateMicrophones()
                        throw RecordingFailure.missingMicrophone
                    }
                }
                if options.camera {
                    let allowed = await AVCaptureDevice.requestAccess(for: .video)
                    try Task.checkCancellation()
                    guard allowed else { throw CameraRecordingError.permission }
                }
                try Task.checkCancellation()
                if delay > 0 {
                    for seconds in stride(from: delay, through: 1, by: -1) {
                        setup.countdown = seconds
                        try await Task.sleep(for: .seconds(1))
                    }
                    setup.countdown = nil
                }
                if options.camera {
                    let webcam = RecordingCamera()
                    camera = webcam
                    try await webcam.start()
                }
                try Task.checkCancellation()
                let url = try archive.reserve()
                reserved = url
                let session = ScreenRecordingSession(outputURL: url)
                session.onEnd = { [weak self] in
                    Task { @MainActor [weak self] in
                        await self?.startTask?.value
                        self?.stop()
                    }
                }
                self.session = session
                try await session.start(source: source, options: options)
                try Task.checkCancellation()
                setup.startedAt = .now
                setup.phase = .recording
                setupWindow?.orderOut(nil)
                automaticZooms = []
                if options.zoomOnClicks { monitorClicks(source: source, since: session.startedAtHostTime) }
                if !terminating { showControls(for: source) }
            } catch {
                await camera?.discard()
                camera = nil
                if let session, session.startedAtHostTime != nil { _ = try? await session.finish() }
                if let reserved { try? FileManager.default.removeItem(at: reserved) }
                self.session = nil
                setup.phase = .ready
                if !Task.isCancelled { report(error) }
            }
        }
    }

    private func finishCamera() async -> Result<RecordingCamera.Clip?, any Error> {
        do { return .success(try await camera?.finish()) }
        catch { return .failure(error) }
    }

    private func monitorClicks(source: RecordingSource, since start: CMTime?) {
        guard let start, let frame = display(for: source)?.frame else { return }
        let bounds: CGRect
        if case .area(_, let area) = source {
            bounds = RecordingSourceGeometry.appKitBounds(of: area, on: frame)
        } else {
            bounds = frame
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            let clock = CMClockGetTime(CMClockGetHostTimeClock())
            let point = NSEvent.mouseLocation
            Task { @MainActor [weak self] in
                guard let self, setup.phase == .recording,
                      let zoom = RecordingZoom.atClick(point, in: bounds, time: (clock - start).seconds, after: automaticZooms.last) else { return }
                automaticZooms.append(zoom)
            }
        }
    }

    private func removeClickMonitor() {
        guard let clickMonitor else { return }
        NSEvent.removeMonitor(clickMonitor)
        self.clickMonitor = nil
    }

    private func report(_ error: any Error) {
        setup.error = error.localizedDescription
    }

    private func updateDisplays() {
        setup.displays = NSScreen.screens.map { screen in
            let size = screen.convertRectToBacking(screen.frame).size
            return RecordingChoice(id: screen.displayID, name: screen.localizedName, frame: screen.frame, pixelSize: size)
        }
        if setup.displayID == nil || !setup.displays.contains(where: { $0.id == setup.displayID }) {
            setup.displayID = NSScreen.underPointer?.displayID ?? setup.displays.first?.id
            setup.area = nil
        } else if let area = setup.area, let frame = setup.displays.first(where: { $0.id == setup.displayID })?.frame {
            setup.area = RecordingSourceGeometry.crop(area, on: frame)
        }
    }

    private static var microphones: [RecordingInputChoice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices
            .map { RecordingInputChoice(id: $0.uniqueID, name: $0.localizedName) }
    }

    private func updateMicrophones() {
        setup.microphones = Self.microphones
        if let id = setup.options.microphoneDeviceID, !setup.microphones.contains(where: { $0.id == id }) {
            setup.options.microphoneDeviceID = nil
        }
    }

    private func updateWindows() {
        guard windowListTask == nil, permission.state == .authorized else { return }
        setup.loadingWindows = true
        windowListTask = Task { [weak self] in
            guard let self else { return }
            defer { setup.loadingWindows = false; windowListTask = nil }
            do {
                let choices = try await sourceCapture.windows()
                guard !Task.isCancelled else { return }
                setup.windows = choices.map { RecordingChoice(id: $0.id, name: $0.title.isEmpty ? "Window \($0.id)" : $0.title, frame: $0.frame) }
                if !setup.windows.contains(where: { $0.id == setup.windowID }) { setup.windowID = setup.windows.first?.id }
            } catch { report(error) }
        }
    }

    private func chooseArea() {
        permission.refresh()
        guard !terminating, !choosingArea, setup.phase == .ready,
              permission.state == .authorized, let id = setup.displayID,
              let initialFrame = display(for: .display(id))?.frame else { return }
        resetPreview()
        setup.error = nil
        choosingArea = true
        setupWindow?.orderOut(nil)
        areaTask = Task { [weak self] in
            guard let self else { return }
            defer { areaTask = nil }
            do {
                let capture = try await sourceCapture.screen(id: id)
                try Task.checkCancellation()
                guard let screen = display(for: .display(id)), screen.frame == initialFrame else {
                    throw RecordingFailure.missingSource
                }
                sourceOverlay.show(screen: screen, capture: capture, captureOnRelease: true) { [weak self] rect, _, _ in
                    guard let self else { return }
                    if let rect, setup.displayID == id, setup.mode == .area {
                        setup.area = RecordingSourceGeometry.crop(rect, on: initialFrame)
                    }
                    returnFromAreaSelection()
                }
            } catch {
                if !Task.isCancelled { report(error) }
                returnFromAreaSelection()
            }
        }
    }

    private func returnFromAreaSelection() {
        choosingArea = false
        if !terminating { present() }
    }

    private func previewSource() {
        permission.refresh()
        guard setup.phase == .ready, permission.state == .authorized, let source = setup.source else { return }
        resetPreview()
        setup.error = nil
        setup.loadingPreview = true
        let request = UUID()
        previewRequest = request
        previewTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if previewRequest == request {
                    setup.loadingPreview = false
                    previewRequest = nil
                    previewTask = nil
                }
            }
            do {
                let image = try await ScreenRecordingSession.sourcePreview(source)
                if !Task.isCancelled, previewRequest == request, source == setup.source {
                    setup.preview = image
                }
            } catch {
                if !Task.isCancelled, previewRequest == request, source == setup.source { report(error) }
            }
        }
    }

    private func resetPreview() {
        previewTask?.cancel()
        previewTask = nil
        previewRequest = nil
        setup.preview = nil
        setup.loadingPreview = false
    }

    private func display(for source: RecordingSource) -> NSScreen? {
        switch source {
        case .display(let id), .area(let id, _): NSScreen.screens.first(where: { $0.displayID == id })
        case .window: nil
        }
    }

    private func showControls(for source: RecordingSource) {
        let size = RecordingControls.preferredSize
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        let host = NSHostingView(rootView: RecordingControls(model: setup, stop: { [weak self] in self?.stop() }))
        host.wantsLayer = true
        host.sizingOptions = []
        panel.contentView = host
        panel.setContentSize(size)
        if let frame = (display(for: source) ?? NSScreen.underPointer)?.visibleFrame {
            panel.setFrameOrigin(CGPoint(x: frame.maxX - size.width - DS.xl, y: frame.maxY - size.height - DS.md))
        }
        controlWindow = panel
        panel.orderFrontRegardless()
        DS.Motion.present(panel, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    private func hideControls() {
        guard let controlWindow else { return }
        self.controlWindow = nil
        DS.Motion.dismiss(controlWindow, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    private func openEditor(_ url: URL, message: String? = nil) {
        let url = url.resolvingSymlinksInPath().standardizedFileURL
        if let existing = editors[url] { existing.present(); return }
        let controller = RecordingEditorController(url: url, initialMessage: message, share: shareReviewLink,
                                                   assistantSettings: assistantSettings,
                                                   onClose: { [weak self] in self?.editors[url] = nil })
        editors[url] = controller
        controller.present()
    }

    static func makeWindow<V: View>(title: String, ideal: CGSize, resizable: Bool = false, view: V) -> NSWindow {
        let available = NSScreen.main?.visibleFrame.size ?? ideal
        let size = DS.fittingWindowSize(preferred: ideal, available: available)
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        if resizable { style.insert(.resizable) }
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        window.contentView = hosting
        window.setContentSize(size)
        window.center()
        return window
    }
}

struct RecordingAction: View {
    let title: String
    let icon: String
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Label { Text(title) } icon: { Icon(icon, size: DS.icon) }
                .font(DS.emphasis)
                .foregroundStyle(DS.onAccent)
                .padding(.horizontal, DS.md)
                .frame(height: DS.toolButtonSize)
                .modifier(GlassSurface(radius: DS.controlRadius, tint: DS.accent, interactive: true))
                .opacity(enabled ? 1 : DS.mutedOpacity)
        }.buttonStyle(PressableStyle())
    }
}
