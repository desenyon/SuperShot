import AVFoundation
import Capture
import DesignSystem
import Document
import Editor
import Export
import SwiftUI

struct RecordingAskFrameInput: Sendable {
    let sourceURL: URL
    let editedTime: TimeInterval
    let edits: RecordingEdits
    var transcript: [RecordingCue] = []

    func render() async throws -> RecordingAskFrameSnapshot {
        guard sourceURL.isFileURL, editedTime.isFinite else { throw RecordingFailure.invalidRange }
        let playback = try await RecordingMedia.playback(sourceURL, edits: edits, transcript: transcript)
        guard let track = try await playback.asset.loadTracks(withMediaType: .video).first else {
            throw RecordingFailure.empty
        }
        let range = try await track.load(.timeRange)
        guard range.duration.isNumeric, range.duration > .zero else { throw RecordingFailure.invalidRange }
        try Task.checkCancellation()

        let generator = AVAssetImageGenerator(asset: playback.asset)
        generator.appliesPreferredTrackTransform = true
        generator.videoComposition = playback.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let timescale: CMTimeScale = 60_000
        let finalSampleTime = max(range.start, range.end - CMTime(value: 1, timescale: timescale))
        let seconds = min(max(range.start.seconds, editedTime), finalSampleTime.seconds)
        let requested = CMTime(seconds: seconds, preferredTimescale: timescale)
        let result = try await generator.image(at: requested)
        try Task.checkCancellation()

        let time = result.actualTime.isNumeric ? result.actualTime.seconds : requested.seconds
        let document = CaptureDocument(original: try ImageExport.encode(result.image), width: result.image.width,
                                       height: result.image.height, source: "Recording frame — \(recordingPlayheadCode(time))")
        return RecordingAskFrameSnapshot(document: document, time: time)
    }
}

struct RecordingAskFrameSnapshot: Sendable {
    let document: CaptureDocument
    let time: TimeInterval
}

@MainActor @Observable
final class RecordingAskSession {
    @MainActor struct Conversation {
        let editor: EditorModel
        let model: AskModel
        let time: TimeInterval

        var hasContent: Bool { !model.messages.isEmpty || !model.regions.isEmpty || !model.draft.isEmpty }
    }

    private(set) var conversation: Conversation?
    private(set) var error: String?
    var isPreparing: Bool { request != nil }

    private let factory: AssistantFactory
    private let load: @Sendable (RecordingAskFrameInput) async throws -> RecordingAskFrameSnapshot
    private var options: AskOptions?
    private var request: UUID?
    @ObservationIgnored private var preparation: Task<Void, Never>?

    init(factory: @escaping AssistantFactory = AssistantWiring.factory,
         load: @escaping @Sendable (RecordingAskFrameInput) async throws -> RecordingAskFrameSnapshot = { try await $0.render() }) {
        self.factory = factory
        self.load = load
    }

    isolated deinit { preparation?.cancel() }

    func updateOptions(_ options: AskOptions?) {
        guard options != self.options else { return }
        let providerChanged = options?.provider != self.options?.provider
        self.options = options
        if let options { conversation?.model.updateOptions(options, changedProvider: providerChanged) }
        else { end() }
    }

    @discardableResult
    func selectFrame(_ input: RecordingAskFrameInput) -> Task<Void, Never>? {
        guard options != nil else { return nil }
        preparation?.cancel()
        let id = UUID()
        request = id
        error = nil
        let work = Task { [weak self, load] in
            defer {
                if self?.request == id {
                    self?.request = nil
                    self?.preparation = nil
                }
            }
            do {
                let frame = try await load(input)
                guard !Task.isCancelled, let self, self.request == id,
                      let options = self.conversation?.model.options ?? self.options else { return }
                self.install(frame, options: options)
            } catch {
                if !Task.isCancelled && self?.request == id {
                    self?.error = "Couldn’t prepare this frame. Try moving the playhead and selecting it again."
                }
            }
        }
        preparation = work
        return work
    }

    private func install(_ frame: RecordingAskFrameSnapshot, options: AskOptions) {
        let editor = EditorModel(document: frame.document)
        let model = AskModel(options: options, factory: factory)
        conversation?.model.end()
        conversation = Conversation(editor: editor, model: model, time: frame.time)
    }

    func end() {
        preparation?.cancel()
        preparation = nil
        request = nil
        error = nil
        conversation?.model.end()
        conversation = nil
    }

    /// Offscreen previews install an in-memory fixture without opening a recording or signing in.
    static func preview(_ frame: RecordingAskFrameSnapshot, options: AskOptions, factory: @escaping AssistantFactory) -> RecordingAskSession {
        let session = RecordingAskSession(factory: factory)
        session.updateOptions(options)
        session.install(frame, options: options)
        return session
    }
}

struct RecordingAskPanel: View {
    let frame: RecordingAskFrameInput?
    let session: RecordingAskSession
    let options: AskOptions?
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduced
    @LocalState private var replacement: RecordingAskFrameInput?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.sm) {
            if let conversation = session.conversation {
                HStack(spacing: DS.sm) {
                    Label {
                        Text("Frame at \(recordingPlayheadCode(conversation.time))").font(DS.mono).lineLimit(1)
                    } icon: { Icon("frame-corners", size: DS.icon) }
                    Spacer(minLength: 0)
                    usePlayhead
                }
                .padding(.horizontal, DS.md).padding(.vertical, DS.sm)
                .modifier(GlassSurface(radius: DS.smallRadius))
                if let error = session.error { errorNotice(error) }
                AskView(model: conversation.model, editor: conversation.editor, close: close, context: .recordingFrame)
                    .id(conversation.editor.document.id)
            } else {
                VStack(alignment: .leading, spacing: DS.md) {
                    HStack {
                        Label { Text("Ask about a frame").font(DS.title) } icon: { Icon("chat-text", size: DS.icon) }
                        Spacer()
                        IconButton("x", label: "Close Ask", size: DS.xl, action: close)
                    }
                    Text("Move to a moment in the recording, then use the playhead to start a conversation about that edited frame.")
                        .font(DS.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let error = session.error { errorNotice(error) }
                    usePlayhead
                }
                .padding(DS.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(GlassSurface(radius: DS.smallRadius))
            }
        }
        .animation(DS.Motion.panel(reduced), value: session.conversation?.editor.document.id)
        .confirmationDialog("Start a new conversation?", isPresented: Binding(
            get: { replacement != nil },
            set: { if !$0 { replacement = nil } }
        ), presenting: replacement) { input in
            Button("Use Playhead", role: .destructive) { session.selectFrame(input) }
            Button("Cancel", role: .cancel) { replacement = nil }
        } message: { _ in
            Text("The conversation and any draft will be replaced after the new frame is ready.")
        }
    }

    private var usePlayhead: some View {
        Button {
            guard let frame else { return }
            if session.conversation?.hasContent == true { replacement = frame }
            else { session.selectFrame(frame) }
        } label: {
            Label {
                Text(session.isPreparing ? "Preparing frame…" : "Use Playhead").lineLimit(1)
            } icon: {
                if session.isPreparing { ProgressView().controlSize(.small).accessibilityHidden(true) }
                else { Icon("frame-corners", size: DS.icon) }
            }
        }
        .buttonStyle(QuietButtonStyle())
        .help("Start a conversation about the edited frame at the playhead")
        .disabled(options == nil || frame == nil || session.isPreparing)
    }

    private func errorNotice(_ error: String) -> some View {
        Label { Text(error).font(DS.caption).fixedSize(horizontal: false, vertical: true) } icon: {
            Icon("warning-circle", size: DS.icon)
        }.foregroundStyle(.secondary)
    }
}
