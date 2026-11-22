import AI
import AppKit
import AVFoundation
import AVKit
import Capture
import DesignSystem
import Document
import Editor
import Export
import Settings
import SwiftUI
import UniformTypeIdentifiers

@MainActor final class RecordingEditorController: NSObject, NSWindowDelegate {
    private let model: RecordingEditorModel
    private let share: ((URL, String, NSWindow?) -> Void)?
    private let assistantSettings: SettingsStore?
    private let onClose: () -> Void
    private var window: NSWindow?

    init(url: URL, initialMessage: String? = nil, share: ((URL, String, NSWindow?) -> Void)? = nil,
         assistantSettings: SettingsStore? = nil, onClose: @escaping () -> Void) {
        model = RecordingEditorModel(url: url)
        model.message = initialMessage
        self.share = share
        self.assistantSettings = assistantSettings
        self.onClose = onClose
    }

    func present() {
        if window == nil {
            let view = RecordingEditorView(model: model, export: { [weak self] in self?.chooseDestination(for: $0) },
                                           exportTranscript: { [weak self] in self?.chooseTranscriptDestination(for: $0) },
                                           share: share == nil ? nil : { [weak self] in self?.shareEditedRecording() },
                                           assistantSettings: assistantSettings)
            let window = RecordingController.makeWindow(title: "Recording Editor", ideal: CGSize(width: 1040, height: 720), resizable: true, view: view)
            window.minSize = CGSize(width: min(window.frame.width, 720), height: min(window.frame.height, 500))
            window.delegate = self
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model.close()
        onClose()
    }

    private func chooseDestination(for format: RecordingFormat) {
        guard let window, !model.exporting, window.attachedSheet == nil else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format == .mp4 ? .mpeg4Movie : .gif]
        panel.nameFieldStringValue = model.url.deletingPathExtension().lastPathComponent + " Edited"
        panel.beginSheetModal(for: window) { [weak self] response in
            if response == .OK, let url = panel.url { self?.model.export(format, to: url) }
        }
    }

    private func chooseTranscriptDestination(for format: RecordingTranscriptFormat) {
        guard let window, window.attachedSheet == nil else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: format.rawValue) ?? .plainText]
        panel.nameFieldStringValue = model.title + "." + format.rawValue
        panel.beginSheetModal(for: window) { [weak self] response in
            if response == .OK, let url = panel.url { self?.model.exportTranscript(format, to: url) }
        }
    }

    private func shareEditedRecording() {
        guard let share else { return }
        let destination = URL.temporaryDirectory.appending(path: "SuperShot-Review-\(UUID().uuidString).mp4")
        model.export(.mp4, to: destination) { [weak self] in
            guard let self else { try? FileManager.default.removeItem(at: destination); return }
            share(destination, model.title, window)
        }
    }
}

@MainActor @Observable final class RecordingEditorModel {
    let url: URL
    let player = AVPlayer()
    let recordingAsk: RecordingAskSession
    private(set) var fullRange: RecordingRange?
    private(set) var pixelSize: CGSize = .zero
    private(set) var frameDuration: TimeInterval = 1.0 / 30
    private(set) var edits: RecordingEdits?
    private(set) var sourceTime: TimeInterval = 0
    private(set) var playing = false
    private(set) var audioTrackCount = 0
    private(set) var hasCamera = false
    private(set) var canUndo = false
    private(set) var canRedo = false
    var selectedAnnotation: UUID?
    var selectedCameraSegment: UUID?
    var cutIn: TimeInterval?
    private(set) var exporting = false
    private(set) var loaded = false
    private(set) var transcript: [RecordingCue] = []
    private(set) var transcribing = false
    var transcriptSelection: Set<UUID> = []
    var message: String?
    var filmstrip: [CGImage] = []
    var sampleImage: CGImage?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var preparation: Task<Void, Never>?
    @ObservationIgnored private var exportTask: Task<Void, Never>?
    @ObservationIgnored private var transcriptTask: Task<Void, Never>?
    @ObservationIgnored private var undo: [RecordingEdits] = []
    @ObservationIgnored private var redo: [RecordingEdits] = []
    @ObservationIgnored private var closed = false
    @ObservationIgnored private var seekRevision = 0
    @ObservationIgnored private var originalFrameDuration: TimeInterval = 1.0 / 30

    var duration: TimeInterval { edits?.duration ?? 0 }
    var canExport: Bool { loaded && !exporting && duration > 0 }
    var title: String { url.deletingPathExtension().lastPathComponent }

    private var sidecar: URL { RecordingMedia.editsURL(for: url) }
    private var transcriptFile: URL { RecordingMedia.transcriptURL(for: url) }

    init(url: URL, recordingAsk: RecordingAskSession = RecordingAskSession()) {
        self.url = url
        self.recordingAsk = recordingAsk
    }

    func load() async {
        guard !loaded else { return }
        do {
            let info = try await RecordingMedia.inspect(url)
            try Task.checkCancellation()
            fullRange = info.range
            pixelSize = info.pixelSize
            originalFrameDuration = info.frameDuration
            frameDuration = info.frameDuration
            audioTrackCount = info.audioTrackCount
            hasCamera = info.hasCamera
            let saved = (try? Data(contentsOf: sidecar)).flatMap { try? JSONDecoder().decode(RecordingEdits.self, from: $0) }
            var initial = saved ?? RecordingEdits(trim: info.range)
            initial.trim = initial.trim.intersection(info.range) ?? info.range
            if initial.kept.isEmpty { initial = RecordingEdits(trim: info.range) }
            edits = initial
            if let data = try? Data(contentsOf: transcriptFile) {
                transcript = (try? JSONDecoder().decode([RecordingCue].self, from: data)) ?? []
            }
            sourceTime = initial.kept.first?.start ?? initial.trim.start
            try await prepare(initial, at: sourceTime)
            try Task.checkCancellation()
            observePlayer()
            loaded = true
            try await loadFilmstrip(range: info.range)
        } catch is CancellationError {
        } catch {
            message = error.localizedDescription
        }
    }

    func close() {
        closed = true
        recordingAsk.end()
        preparation?.cancel()
        exportTask?.cancel()
        transcriptTask?.cancel()
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player.replaceCurrentItem(with: nil)
    }

    func playOrPause() {
        guard loaded else { return }
        if playing { player.pause() }
        else {
            if player.currentTime().seconds >= duration - 0.04 { player.seek(to: .zero) }
            player.play()
        }
        playing.toggle()
    }

    func seek(_ time: TimeInterval) {
        guard let edits, let fullRange else { return }
        player.pause()
        playing = false
        seekRevision &+= 1
        sourceTime = min(fullRange.end, max(fullRange.start, time))
        let edited = min(duration, edits.editedTime(forSourceTime: sourceTime))
        player.seek(to: CMTime(seconds: edited, preferredTimescale: 6000), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func setStart() {
        guard let edits, let range = RecordingRange(start: sourceTime, end: edits.trim.end) else { return }
        change { $0.trim = range }
    }

    func setEnd() {
        guard let edits, let range = RecordingRange(start: edits.trim.start, end: sourceTime) else { return }
        change { $0.trim = range }
    }

    func resetTrim() {
        guard let fullRange else { return }
        change { $0.trim = fullRange; $0.cuts.removeAll() }
    }

    func addZoom(at center: CGPoint = CGPoint(x: 0.5, y: 0.5)) {
        guard let part = edits?.kept.first(where: { $0.start <= sourceTime && sourceTime < $0.end }),
              let range = RecordingRange(start: sourceTime, end: min(sourceTime + 2, part.end)) else { return }
        change { $0.zooms.append(RecordingZoom(range: range, center: center)) }
    }

    func removeZoom(_ index: Int) {
        change { if $0.zooms.indices.contains(index) { $0.zooms.remove(at: index) } }
    }
    func setPerspective(_ value: RecordingPerspective) { change { $0.perspective = value } }
    func setCaptionStyle(_ style: RecordingCaptionStyle?) { change { $0.captionStyle = style } }
    func setCameraLayout(_ layout: RecordingCameraLayout) { change { $0.cameraLayout = layout } }

    func step(_ offset: TimeInterval) {
        guard let edits else { return }
        let time = min(edits.duration, max(0, edits.editedTime(forSourceTime: sourceTime) + offset))
        seek(edits.sourceTime(forEditedTime: time))
    }

    func commitCut() {
        guard let cutIn, let range = RecordingRange(start: min(cutIn, sourceTime), end: max(cutIn, sourceTime)) else { return }
        self.cutIn = nil
        cut([range])
    }

    var canPlaceTimedEdit: Bool {
        edits?.kept.contains(where: { $0.start <= sourceTime && sourceTime < $0.end }) == true
    }

    private func rangeAtPlayhead() -> RecordingRange? {
        guard canPlaceTimedEdit, let edits else { return nil }
        return RecordingRange(start: sourceTime, end: min(sourceTime + 3, edits.trim.end))
    }

    func addAnnotation(_ kind: RecordingAnnotation.Kind, from start: CGPoint, to end: CGPoint,
                       ink: RecordingAnnotation.Ink) {
        guard let range = rangeAtPlayhead() else { return }
        let item = RecordingAnnotation(kind: kind, range: range, start: start, end: end, ink: ink, text: kind == .text ? "Label" : "")
        change { $0.annotations = ($0.annotations ?? []) + [item] }
        selectedAnnotation = item.id
    }

    func editAnnotation(_ id: UUID, _ update: (inout RecordingAnnotation) -> Void) {
        change { edits in
            guard var items = edits.annotations, let index = items.firstIndex(where: { $0.id == id }) else { return }
            update(&items[index])
            edits.annotations = items
        }
    }

    func removeAnnotation(_ id: UUID) {
        change { $0.annotations?.removeAll { $0.id == id } }
        if selectedAnnotation == id { selectedAnnotation = nil }
    }

    func addCameraSegment(_ layout: RecordingCameraLayout) {
        guard let range = rangeAtPlayhead() else { return }
        let segment = RecordingCameraSegment(range: range, layout: layout)
        change { $0.cameraSegments = ($0.cameraSegments ?? []) + [segment] }
        selectedCameraSegment = segment.id
    }

    func editCameraSegment(_ id: UUID, _ update: (inout RecordingCameraSegment) -> Void) {
        change { edits in
            guard var items = edits.cameraSegments, let index = items.firstIndex(where: { $0.id == id }) else { return }
            update(&items[index])
            edits.cameraSegments = items
        }
    }

    func removeCameraSegment(_ id: UUID) {
        change { $0.cameraSegments?.removeAll { $0.id == id } }
        if selectedCameraSegment == id { selectedCameraSegment = nil }
    }

    func setAudioLevel(_ value: Float, index: Int) {
        guard value.isFinite, (0..<audioTrackCount).contains(index) else { return }
        change {
            if $0.audioLevels.count <= index { $0.audioLevels.append(contentsOf: repeatElement(1, count: index + 1 - $0.audioLevels.count)) }
            $0.audioLevels[index] = min(1, max(0, value))
        }
    }

    func undoEdit() {
        guard let last = undo.popLast(), let current = edits else { return }
        redo.append(current)
        canUndo = !undo.isEmpty
        canRedo = true
        apply(last)
    }

    func redoEdit() {
        guard let next = redo.popLast(), let current = edits else { return }
        undo.append(current)
        canUndo = true
        canRedo = !redo.isEmpty
        apply(next)
    }

    func export(_ format: RecordingFormat, to destination: URL, forSharing: (() -> Void)? = nil) {
        guard canExport, let edits else { return }
        exporting = true
        message = nil
        let transcript = transcript
        exportTask = Task { [weak self] in
            guard let self else { return }
            defer { exporting = false; exportTask = nil }
            do {
                try await RecordingMedia.export(url, to: destination, format: format, edits: edits, transcript: transcript)
                if let forSharing {
                    do {
                        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
                        forSharing()
                    } catch {
                        try? FileManager.default.removeItem(at: destination)
                        throw error
                    }
                } else { message = "Saved \(destination.lastPathComponent)" }
            } catch is CancellationError {
                message = "Export cancelled"
            } catch { message = error.localizedDescription }
        }
    }

    func cancelExport() { exportTask?.cancel() }

    func transcribe(track: Int) {
        guard !transcribing, transcript.isEmpty else { return }
        transcribing = true
        message = nil
        transcriptTask = Task { [weak self] in
            guard let self else { return }
            defer { transcribing = false; transcriptTask = nil }
            do {
                let cues = try await RecordingTranscript.transcribe(url, trackIndex: track)
                try Task.checkCancellation()
                transcript = cues
                persistTranscript()
            } catch is CancellationError {
            } catch { message = error.localizedDescription }
        }
    }

    func cancelTranscription() { transcriptTask?.cancel() }

    func correct(_ cue: UUID, text: String) {
        let correction = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !correction.isEmpty, let index = transcript.firstIndex(where: { $0.id == cue }), transcript[index].text != correction else { return }
        transcript[index].text = correction
        persistTranscript()
        if let edits, edits.captionStyle != nil { apply(edits) }
    }

    func cutSelectedWords() {
        let ranges = transcript.filter { transcriptSelection.contains($0.id) }.map(\.range)
        cut(ranges)
        transcriptSelection.removeAll()
    }

    func removeFillers() { cut(RecordingTranscript.fillerCuts(transcript)) }
    func shortenPauses() { cut(RecordingTranscript.pauseCuts(transcript)) }

    private func cut(_ ranges: [RecordingRange]) {
        change { edits in
            edits.cuts.append(contentsOf: ranges.filter { !edits.cuts.contains($0) })
        }
    }

    func exportTranscript(_ format: RecordingTranscriptFormat, to destination: URL) {
        guard let edits else { return }
        do {
            try RecordingMedia.validateDestination(destination, source: url)
            let contents = RecordingTranscript.contents(transcript, in: edits, as: format)
            try contents.write(to: destination, atomically: true, encoding: .utf8)
            message = "Saved \(destination.lastPathComponent)"
        } catch { message = error.localizedDescription }
    }

    private func persistTranscript() {
        do {
            try JSONEncoder().encode(transcript).write(to: transcriptFile, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: transcriptFile.path)
        } catch { message = "Couldn’t keep the transcript. \(error.localizedDescription)" }
    }

    private func change(_ update: (inout RecordingEdits) -> Void) {
        guard let current = edits else { return }
        var next = current
        update(&next)
        guard next != current else { return }
        guard next.duration >= 1.0 / 30 else { message = RecordingFailure.invalidRange.errorDescription; return }
        undo.append(current)
        redo.removeAll()
        canUndo = true
        canRedo = false
        apply(next)
    }

    private func apply(_ next: RecordingEdits) {
        edits = next
        message = nil
        do {
            try JSONEncoder().encode(next).write(to: sidecar, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sidecar.path)
        } catch { message = "Couldn’t keep these edits. \(error.localizedDescription)" }
        preparation?.cancel()
        let time = sourceTime
        preparation = Task { [weak self] in
            do { try await self?.prepare(next, at: time) }
            catch is CancellationError { }
            catch { self?.message = error.localizedDescription }
        }
    }

    private func prepare(_ edits: RecordingEdits, at sourceTime: TimeInterval) async throws {
        let revision = seekRevision
        let playback = try await RecordingMedia.playback(url, edits: edits, transcript: transcript)
        try Task.checkCancellation()
        guard !closed else { throw CancellationError() }
        let item = AVPlayerItem(asset: playback.asset)
        item.videoComposition = playback.videoComposition
        item.audioMix = playback.audioMix
        if let seconds = playback.videoComposition?.frameDuration.seconds, seconds.isFinite, seconds > 0 {
            frameDuration = seconds
        } else { frameDuration = originalFrameDuration }
        player.pause()
        playing = false
        player.replaceCurrentItem(with: item)
        seek(revision == seekRevision ? sourceTime : self.sourceTime)
    }

    private func observePlayer() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 24), queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self, playing, let edits else { return }
                sourceTime = edits.sourceTime(forEditedTime: time.seconds)
                if player.rate == 0 { playing = false }
            }
        }
    }

    private func loadFilmstrip(range: RecordingRange) async throws {
        let thumbnails = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        thumbnails.appliesPreferredTrackTransform = true
        thumbnails.maximumSize = CGSize(width: 240, height: 120)
        for index in 0..<8 {
            try Task.checkCancellation()
            let time = CMTime(seconds: range.start + range.duration * Double(index) / 8, preferredTimescale: 6000)
            if let frame = try? await thumbnails.image(at: time) { filmstrip.append(frame.image) }
        }
    }

    static func fixture(_ image: CGImage, showsTranscript: Bool = false, showsMarkup: Bool = false, showsCamera: Bool = false,
                        askOptions: AskOptions? = nil) -> RecordingEditorModel {
        let url = URL(filePath: "/preview/Website walkthrough.mp4")
        let model: RecordingEditorModel
        if let askOptions, let data = try? ImageExport.encode(image) {
            let document = CaptureDocument(original: data, width: image.width, height: image.height, source: "Recording frame — 0:05")
            let session = RecordingAskSession.preview(RecordingAskFrameSnapshot(document: document, time: 5),
                                                      options: askOptions, factory: { PreviewAssistantService(provider: $0) })
            model = RecordingEditorModel(url: url, recordingAsk: session)
        } else {
            model = RecordingEditorModel(url: url)
        }
        let range = RecordingRange(start: 0, end: 24)!
        var edits = RecordingEdits(trim: RecordingRange(start: 2, end: 20)!)
        edits.zooms = [RecordingZoom(range: RecordingRange(start: 7, end: 9)!)]
        if showsMarkup {
            let annotation = RecordingAnnotation(kind: .outline, range: RecordingRange(start: 6, end: 10)!,
                                                 start: CGPoint(x: 0.28, y: 0.23), end: CGPoint(x: 0.69, y: 0.57))
            edits.annotations = [annotation]
            model.selectedAnnotation = annotation.id
        }
        if showsCamera {
            let segment = RecordingCameraSegment(range: RecordingRange(start: 7, end: 12)!, layout: .circle)
            edits.cameraSegments = [segment]
            model.selectedCameraSegment = segment.id
        }
        model.fullRange = range
        model.edits = edits
        model.audioTrackCount = 2
        model.hasCamera = true
        model.sourceTime = 7
        model.pixelSize = CGSize(width: image.width, height: image.height)
        model.filmstrip = Array(repeating: image, count: 8)
        model.sampleImage = image
        model.loaded = true
        if showsTranscript {
            model.transcript = ["The settings panel keeps", "common options close at hand.", "Open the library to find", "the original capture."].enumerated().map { index, text in
                let start = 3.0 + Double(index) * 2
                return RecordingCue(text: text, range: RecordingRange(start: start, end: start + 1.5)!)
            }
        }
        return model
    }
}

struct RecordingEditorView: View {
    enum Inspector: String, CaseIterable {
        case edit = "Edit"
        case markup = "Annotate"
        case camera = "Camera"
        case transcript = "Transcript"
        case ask = "Ask"

        var icon: String {
            switch self {
            case .edit: "scissors"
            case .markup: "note-pencil"
            case .camera: "video-camera"
            case .transcript: "text-align-left"
            case .ask: "chat-circle-dots"
            }
        }
    }

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var model: RecordingEditorModel
    let export: (RecordingFormat) -> Void
    var exportTranscript: (RecordingTranscriptFormat) -> Void = { _ in }
    var share: (() -> Void)?
    var assistantSettings: SettingsStore?
    var previewAskOptions: AskOptions?
    @LocalState var activeInspector: Inspector = .edit
    @LocalState private var placing: RecordingAnnotation.Kind?
    @LocalState private var zoomFocus = false
    @LocalState private var ink: RecordingAnnotation.Ink = .blue

    private var askOptions: AskOptions? {
        previewAskOptions ?? assistantSettings.flatMap { AssistantWiring.options($0.preferences.assistant) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.md) {
            header
            HStack(alignment: .top, spacing: DS.md) {
                inspectorPicker
                canvas.frame(maxWidth: .infinity, maxHeight: .infinity)
                inspector.frame(width: activeInspector == .ask ? DS.Ask.editorWidth : DS.inspectorWidth)
            }
            RecordingTimeline(model: model, selectAnnotation: { id in
                model.selectedAnnotation = id
                activeInspector = .markup
            }, selectCamera: { id in
                model.selectedCameraSegment = id
                activeInspector = .camera
            })
            playbackControls
        }
        .padding(DS.lg)
        .padding(.top, DS.lg)
        .background(WorkspaceBackground())
        .task { await model.load() }
        .onChange(of: askOptions, initial: true) { _, options in
            model.recordingAsk.updateOptions(options)
            if options == nil, activeInspector == .ask { activeInspector = .edit }
        }
        .onChange(of: activeInspector) { _, value in
            if value != .markup { placing = nil }
            if value != .edit { zoomFocus = false }
        }
        .animation(DS.Motion.panel(reduceMotion), value: model.exporting)
        .animation(DS.Motion.panel(reduceMotion), value: activeInspector)
    }

    private var header: some View {
        HStack(spacing: DS.md) {
            WorkspaceHeader(title: model.title, subtitle: mediaSummary, icon: "film-strip")
                .lineLimit(1)
            Spacer(minLength: 0)
            if model.exporting {
                ProgressView().controlSize(.small).accessibilityLabel("Exporting recording")
                Button("Cancel export", action: model.cancelExport).buttonStyle(QuietButtonStyle())
            } else {
                Menu {
                    Button("Export MP4…") { export(.mp4) }
                    Button("Export GIF…") { export(.gif) }.disabled(model.duration > RecordingMedia.maxGIFDuration)
                    if let share {
                        Divider()
                        Button("Share Edited Recording…", action: share)
                    }
                    if !model.transcript.isEmpty {
                        Divider()
                        Button("Export transcript…") { exportTranscript(.text) }
                        Button("Export SRT…") { exportTranscript(.srt) }
                        Button("Export WebVTT…") { exportTranscript(.vtt) }
                    }
                } label: {
                    Label { Text("Export").font(DS.emphasis) } icon: { Icon("download-simple", size: DS.icon) }
                        .padding(.horizontal, DS.sm)
                }
                .menuStyle(.borderlessButton)
                .fixedSize().disabled(!model.canExport)
                .padding(DS.sm)
                .modifier(GlassSurface(radius: DS.smallRadius, tint: DS.accent.opacity(DS.outlineOpacity), interactive: true))
            }
        }
    }

    private var mediaSummary: String? {
        guard model.pixelSize.width > 0 else { return nil }
        return "\(Int(model.pixelSize.width)) × \(Int(model.pixelSize.height))  ·  \(recordingTimeCode(model.duration))"
    }

    private var inspectorPicker: some View {
        ViewThatFits(in: .vertical) {
            recordingTools(showLabels: true)
            recordingTools(showLabels: false)
            ScrollView { recordingTools(showLabels: false) }.scrollIndicators(.hidden)
        }
        .frame(width: DS.xxl + DS.xl)
        .modifier(GlassSurface(radius: DS.smallRadius, showsShadow: false))
        .accessibilityLabel("Recording tools")
    }

    private func recordingTools(showLabels: Bool) -> some View {
        VStack(spacing: DS.xs) {
            ForEach(Inspector.allCases.filter { $0 != .ask || askOptions != nil }, id: \.self) { pane in
                Button {
                    activeInspector = pane
                } label: {
                    VStack(spacing: DS.xs) {
                        Icon(pane.icon, size: DS.lg).accessibilityHidden(true)
                        if showLabels {
                            Text(pane.rawValue).font(DS.caption).lineLimit(1).minimumScaleFactor(0.9)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: showLabels ? DS.xxl + DS.sm : DS.toolButton)
                    .foregroundStyle(activeInspector == pane ? DS.actionInk(scheme) : .secondary)
                    .background(activeInspector == pane ? DS.accent.opacity(DS.outlineOpacity) : .clear,
                                in: RoundedRectangle(cornerRadius: DS.controlRadius))
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(pane.rawValue)
                .help(pane.rawValue)
                .accessibilityAddTraits(activeInspector == pane ? .isSelected : [])
            }
        }
        .padding(DS.xs)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var canvas: some View {
        ZStack {
            DS.black
            if let image = model.sampleImage {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
            } else if model.loaded {
                RecordingPlayer(player: model.player)
            } else if model.message == nil {
                ProgressView().tint(DS.white).accessibilityLabel("Loading recording")
            }
            if activeInspector == .markup {
                RecordingMarkupCanvas(model: model, placing: $placing, ink: ink)
            }
            if zoomFocus {
                RecordingZoomFocusView(pixelSize: model.pixelSize) { point in
                    model.addZoom(at: point)
                    zoomFocus = false
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.smallRadius))
        .overlay(RoundedRectangle(cornerRadius: DS.smallRadius).strokeBorder(DS.hairline(scheme)).allowsHitTesting(false))
    }

    @ViewBuilder private var inspector: some View {
        if activeInspector == .ask {
            RecordingAskPanel(frame: askInput, session: model.recordingAsk, options: askOptions, close: { activeInspector = .edit })
                .frame(maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.lg) {
                    Label { Text(activeInspector.rawValue).font(DS.emphasis).accessibilityAddTraits(.isHeader) } icon: {
                        Icon(activeInspector.icon, size: DS.icon)
                    }
                    Hairline()
                    switch activeInspector {
                    case .edit:
                        trimSection
                        Hairline()
                        motionSection
                        if model.audioTrackCount > 0 { Hairline(); audioSection }
                    case .markup:
                        RecordingMarkupOptions(model: model, placing: $placing, ink: $ink)
                    case .camera:
                        RecordingCameraOptions(model: model)
                    case .transcript:
                        RecordingTranscriptPane(model: model)
                    case .ask: EmptyView()
                    }
                }
                .padding(DS.md)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .modifier(GlassSurface(radius: DS.groupRadius, showsShadow: false))
        }
    }

    private var askInput: RecordingAskFrameInput? {
        guard model.loaded, model.sampleImage == nil, let edits = model.edits else { return nil }
        return RecordingAskFrameInput(sourceURL: model.url, editedTime: edits.editedTime(forSourceTime: model.sourceTime),
                                      edits: edits, transcript: model.transcript)
    }

    private var trimSection: some View {
        VStack(alignment: .leading, spacing: DS.sm) {
            Text("Trim").font(DS.emphasis)
            HStack(spacing: DS.xs) {
                Button("Set start", action: model.setStart).buttonStyle(QuietButtonStyle())
                Button("Set end", action: model.setEnd).buttonStyle(QuietButtonStyle())
            }.disabled(!model.loaded)
            HStack(spacing: DS.xs) {
                if let cutIn = model.cutIn {
                    Button("Cut to playhead", action: model.commitCut)
                        .buttonStyle(QuietButtonStyle())
                        .disabled(abs(cutIn - model.sourceTime) < 1.0 / 30)
                    IconButton("x", label: "Cancel cut range", size: DS.xl) { model.cutIn = nil }
                } else {
                    Button("Mark start of cut") { model.cutIn = model.sourceTime }
                        .buttonStyle(QuietButtonStyle()).disabled(!model.loaded)
                }
            }
            if let trim = model.edits?.trim {
                HStack {
                    Text("\(recordingTimeCode(trim.start)) – \(recordingTimeCode(trim.end))").font(DS.mono).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("Reset", action: model.resetTrim).buttonStyle(.plain).font(DS.body)
                }
            }
        }
    }

    private var motionSection: some View {
        VStack(alignment: .leading, spacing: DS.sm) {
            Text("Motion").font(DS.emphasis)
            Picker("Perspective", selection: Binding(get: { model.edits?.perspective ?? .flat }, set: model.setPerspective)) {
                ForEach(RecordingPerspective.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.font(DS.body).disabled(!model.loaded)
            if zoomFocus {
                Text("Click the video to set the zoom focus.").font(DS.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Use center") { model.addZoom(); zoomFocus = false }.buttonStyle(QuietButtonStyle())
                    Button("Cancel") { zoomFocus = false }.buttonStyle(.plain)
                }
            } else {
                Button("Add zoom at playhead") {
                    if model.playing { model.playOrPause() }
                    zoomFocus = true
                }
                .buttonStyle(QuietButtonStyle()).disabled(!model.canPlaceTimedEdit)
            }
            ForEach(Array((model.edits?.zooms ?? []).enumerated()), id: \.offset) { index, zoom in
                HStack(spacing: DS.xs) {
                    Icon("magnifying-glass-plus", size: DS.icon)
                    Button("\(recordingPlayheadCode(zoom.range.start))–\(recordingPlayheadCode(zoom.range.end))") {
                        model.seek(zoom.range.start)
                    }.buttonStyle(.plain).font(DS.mono)
                    Spacer(minLength: 0)
                    IconButton("x", label: "Remove zoom at \(recordingTimeCode(zoom.range.start))", size: DS.xl) { model.removeZoom(index) }
                }
            }
        }
    }

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: DS.sm) {
            Text("Audio").font(DS.emphasis)
            ForEach(0..<model.audioTrackCount, id: \.self) { index in
                RecordingVolume(model: model, index: index)
            }
        }
    }

    private var playbackControls: some View {
        HStack(spacing: DS.sm) {
            IconButton("caret-left", label: "Back one frame") { model.step(-model.frameDuration) }
                .keyboardShortcut(.leftArrow, modifiers: .option).disabled(!model.loaded)
            IconButton(model.playing ? "pause" : "play", label: model.playing ? "Pause" : "Play", action: model.playOrPause)
                .keyboardShortcut(.space, modifiers: []).disabled(!model.loaded)
            IconButton("caret-right", label: "Forward one frame") { model.step(model.frameDuration) }
                .keyboardShortcut(.rightArrow, modifiers: .option).disabled(!model.loaded)
            if let edits = model.edits {
                Text("\(recordingPlayheadCode(edits.editedTime(forSourceTime: model.sourceTime))) / \(recordingTimeCode(model.duration))")
                    .font(DS.mono).foregroundStyle(.secondary)
                    .accessibilityLabel("Edited playhead")
            }
            IconButton("arrow-counter-clockwise", label: "Undo recording edit", action: model.undoEdit)
                .keyboardShortcut("z", modifiers: .command).disabled(!model.canUndo)
            IconButton("arrow-clockwise", label: "Redo recording edit", action: model.redoEdit)
                .keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!model.canRedo)
            Spacer(minLength: 0)
            if let message = model.message {
                Text(message).font(DS.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
            }
        }
        .padding(.horizontal, DS.sm).padding(.vertical, DS.xs)
        .modifier(GlassSurface(radius: DS.smallRadius, showsShadow: false))
    }
}

private struct RecordingTranscriptPane: View {
    @Bindable var model: RecordingEditorModel
    @LocalState private var track = 0
    @LocalState private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DS.md) {
            if model.transcript.isEmpty {
                emptyState
            } else {
                Picker("Captions", selection: Binding(get: { model.edits?.captionStyle }, set: model.setCaptionStyle)) {
                    Text("Off").tag(nil as RecordingCaptionStyle?)
                    ForEach(RecordingCaptionStyle.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                }.font(DS.body)
                TextField("Find a word or phrase", text: $search).font(DS.body)
                HStack {
                    Button("Cut selected", action: model.cutSelectedWords).buttonStyle(QuietButtonStyle())
                        .disabled(model.transcriptSelection.isEmpty)
                    Menu {
                        Button("Remove filler words", action: model.removeFillers)
                        Button("Shorten long pauses", action: model.shortenPauses)
                    } label: { Icon("dots-three", size: DS.iconSize).accessibilityLabel("Transcript actions") }
                        .menuStyle(.borderlessButton).fixedSize()
                }
                LazyVStack(alignment: .leading, spacing: DS.sm) {
                    ForEach(model.transcript.filter { search.isEmpty || $0.text.localizedCaseInsensitiveContains(search) }) { cue in
                        RecordingCueRow(model: model, cue: cue)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DS.sm) {
            if model.transcribing {
                ProgressView("Transcribing on this Mac…").controlSize(.small).font(DS.body)
                Button("Cancel", action: model.cancelTranscription).buttonStyle(QuietButtonStyle())
            } else if model.audioTrackCount == 0 {
                Text("This recording has no audio.").font(DS.body).foregroundStyle(.secondary)
            } else {
                Text("Create an editable transcript with on-device speech recognition. macOS may download a language model.")
                    .font(DS.body).foregroundStyle(.secondary)
                if model.audioTrackCount > 1 {
                    Picker("Audio track", selection: $track) {
                        ForEach(0..<model.audioTrackCount, id: \.self) { Text("Track \($0 + 1)").tag($0) }
                    }.font(DS.body)
                }
                Button("Generate transcript") { model.transcribe(track: track) }.buttonStyle(QuietButtonStyle())
            }
        }
    }
}

private struct RecordingCueRow: View {
    let model: RecordingEditorModel
    let cue: RecordingCue
    @LocalState private var correction = ""
    @FocusState private var correcting: Bool

    var body: some View {
        let cut = model.edits?.kept.contains { $0.intersection(cue.range) != nil } == false
        HStack(spacing: DS.sm) {
            Toggle("Select \(cue.text)", isOn: Binding(get: { model.transcriptSelection.contains(cue.id) }, set: { value in
                if value { model.transcriptSelection.insert(cue.id) }
                else { model.transcriptSelection.remove(cue.id) }
            })).toggleStyle(.checkbox).labelsHidden().disabled(cut)
            Button(recordingTimeCode(cue.range.start)) { model.seek(cue.range.start) }.buttonStyle(.plain).font(DS.mono)
                .help("Jump to \(recordingTimeCode(cue.range.start))")
            TextField("Transcript text", text: $correction, axis: .vertical)
                .font(DS.body).strikethrough(cut)
                .lineLimit(1...3)
                .textFieldStyle(.plain)
                .focused($correcting)
                .onChange(of: correcting) { _, focused in
                    if !focused && correction != cue.text { model.correct(cue.id, text: correction) }
                }
                .onSubmit { model.correct(cue.id, text: correction) }
                .onChange(of: cue.text, initial: true) { _, text in correction = text }
        }
        .opacity(cut ? DS.mutedOpacity : 1)
    }
}

private struct RecordingVolume: View {
    let model: RecordingEditorModel
    let index: Int
    @LocalState private var level: Float = 1
    @LocalState private var previousLevel: Float = 1

    var body: some View {
        VStack(alignment: .leading, spacing: DS.xs) {
            HStack {
                Text(model.audioTrackCount == 1 ? "Volume" : "Track \(index + 1)").font(DS.body)
                Spacer()
                Text("\(Int((level * 100).rounded()))%").font(DS.mono).foregroundStyle(.secondary)
                IconButton(level == 0 ? "speaker-slash" : "speaker-high",
                           label: level == 0 ? "Unmute track \(index + 1)" : "Mute track \(index + 1)", size: DS.xl) {
                    model.setAudioLevel(level == 0 ? previousLevel : 0, index: index)
                }
            }
            Slider(value: $level, in: 0...1) { Text("Volume for track \(index + 1)") } onEditingChanged: { editing in
                if !editing { model.setAudioLevel(level, index: index) }
            }.labelsHidden().tint(DS.accent)
        }.onChange(of: model.edits?.audioLevels, initial: true) { _, levels in
            let stored = levels.flatMap { $0.indices.contains(index) ? $0[index] : nil } ?? 1
            level = stored.isFinite ? min(1, max(0, stored)) : 1
            if level > 0 { previousLevel = level }
        }
    }
}

private struct RecordingTimeline: View {
    @Environment(\.colorScheme) private var scheme
    let model: RecordingEditorModel
    let selectAnnotation: (UUID) -> Void
    let selectCamera: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.xs) {
            if let full = model.fullRange {
                HStack {
                    Text("Timeline").font(DS.emphasis)
                    Spacer()
                    Text("Source \(recordingPlayheadCode(model.sourceTime)) / \(recordingTimeCode(full.end))")
                        .font(DS.mono).foregroundStyle(.secondary)
                }
            }
            if hasEffectLanes {
                HStack(spacing: DS.xs) {
                    laneLabel("Video")
                    filmstrip
                }
            } else {
                filmstrip
            }
            if let full = model.fullRange, let edits = model.edits {
                if let items = edits.annotations, !items.isEmpty {
                    lane("Annotate", items: items, full: full, range: \.range, selected: model.selectedAnnotation, select: selectAnnotation)
                }
                if let items = edits.cameraSegments, !items.isEmpty {
                    lane("Camera", items: items, full: full, range: \.range, selected: model.selectedCameraSegment, select: selectCamera)
                }
            }
        }
        .padding(DS.sm)
        .modifier(GlassSurface(radius: DS.groupRadius, showsShadow: false))
    }

    private var hasEffectLanes: Bool {
        model.edits?.annotations?.isEmpty == false || model.edits?.cameraSegments?.isEmpty == false
    }

    private func laneLabel(_ title: String) -> some View {
        Text(title).font(DS.caption).foregroundStyle(.secondary).frame(width: DS.xxl * 1.5, alignment: .leading)
    }

    private func lane<Item: Identifiable>(_ title: String, items: [Item], full: RecordingRange,
                                         range: KeyPath<Item, RecordingRange>, selected: UUID?,
                                         select: @escaping (UUID) -> Void) -> some View where Item.ID == UUID {
        HStack(spacing: DS.xs) {
            laneLabel(title)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: DS.xs).fill(DS.card(scheme))
                    ForEach(items) { item in
                        if let part = item[keyPath: range].intersection(full) {
                            Button {
                                select(item.id)
                                model.seek(part.start)
                            } label: {
                                RoundedRectangle(cornerRadius: DS.xs)
                                    .fill(DS.accent.opacity(selected == item.id ? 0.8 : 0.38))
                            }
                            .buttonStyle(.plain)
                            .frame(width: max(DS.xs, geo.size.width * part.duration / full.duration))
                            .offset(x: geo.size.width * (part.start - full.start) / full.duration)
                            .accessibilityLabel("\(title) at \(recordingPlayheadCode(part.start))")
                        }
                    }
                }.clipped()
            }
        }.frame(height: DS.lg)
    }

    private var filmstrip: some View {
        GeometryReader { geometry in
            if let full = model.fullRange {
                let width = geometry.size.width
                let height = geometry.size.height
                ZStack(alignment: .topLeading) {
                    HStack(spacing: DS.stroke) {
                        ForEach(Array(model.filmstrip.enumerated()), id: \.offset) { _, image in
                            GeometryReader { frame in
                                Image(decorative: image, scale: 1).resizable().scaledToFill()
                                    .frame(width: frame.size.width, height: frame.size.height).clipped()
                            }
                        }
                    }
                    .background(DS.card(scheme))
                    .overlay(DS.black.opacity(DS.shadowOpacity))
                    ForEach(Array((model.edits?.kept ?? []).enumerated()), id: \.offset) { _, range in
                        RoundedRectangle(cornerRadius: DS.controlRadius, style: .continuous)
                            .strokeBorder(DS.accent, lineWidth: DS.stroke * 2)
                            .frame(width: width * range.duration / full.duration, height: height)
                            .offset(x: width * (range.start - full.start) / full.duration)
                    }
                    ForEach(Array((model.edits?.zooms ?? []).enumerated()), id: \.offset) { _, zoom in
                        let range = zoom.range
                        RoundedRectangle(cornerRadius: DS.xs)
                            .fill(DS.accent)
                            .frame(width: width * range.duration / full.duration, height: DS.xs)
                            .offset(x: width * (range.start - full.start) / full.duration, y: height - DS.md)
                    }
                    if let cutIn = model.cutIn {
                        Rectangle().fill(DS.danger.opacity(DS.outlineOpacity * 2))
                            .frame(width: max(DS.stroke * 2, width * abs(cutIn - model.sourceTime) / full.duration))
                            .offset(x: width * (min(cutIn, model.sourceTime) - full.start) / full.duration)
                    }
                    Rectangle().fill(DS.white).frame(width: DS.stroke * 2)
                        .offset(x: min(width - DS.stroke * 2, width * (model.sourceTime - full.start) / full.duration))
                }
                .clipShape(RoundedRectangle(cornerRadius: DS.controlRadius, style: .continuous))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    guard width > 0 else { return }
                    let fraction = min(1, max(0, value.location.x / width))
                    model.seek(full.start + fraction * full.duration)
                })
                .accessibilityElement()
                .accessibilityLabel("Recording timeline")
                .accessibilityValue(recordingTimeCode(model.sourceTime))
                .accessibilityAdjustableAction { direction in
                    let offset: Double = direction == .increment ? 1 : -1
                    model.seek(min(full.end, max(full.start, model.sourceTime + offset)))
                }
            }
        }.frame(height: DS.toolButtonSize + DS.lg)
    }
}

private struct RecordingPlayer: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) { view.player = player }
}

func recordingPlayheadCode(_ seconds: TimeInterval) -> String {
    let fraction = seconds.isFinite ? Int((max(0, seconds).truncatingRemainder(dividingBy: 1) * 100).rounded(.down)) : 0
    return recordingTimeCode(seconds) + String(format: ".%02d", fraction)
}

func recordingTimeCode(_ seconds: TimeInterval) -> String {
    let total = seconds.isFinite ? Int(max(0, seconds).rounded(.down)) : 0
    return String(format: "%d:%02d", total / 60, total % 60)
}
