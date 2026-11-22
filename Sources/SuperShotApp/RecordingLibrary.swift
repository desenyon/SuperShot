import AppKit
import AVFoundation
import Capture
import DesignSystem
import Editor
import SwiftUI

struct RecordingLibraryView: View {
    @Environment(\.colorScheme) private var scheme
    @LocalState private var files: [URL] = []
    @LocalState private var message: String?
    @LocalState private var loading = true
    @LocalState private var refresh = 0
    @LocalState private var query = ""
    @LocalState private var newestFirst = true
    let archive: RecordingArchive
    let open: (URL) -> Void
    let record: () -> Void
    var fixtures: [URL: CGImage] = [:]
    var previewOnly = false

    private var matchingFiles: [URL] {
        let source = fixtures.isEmpty ? files : fixtures.keys.sorted { $0.lastPathComponent > $1.lastPathComponent }
        let titles = source.filter { query.isEmpty || $0.lastPathComponent.localizedCaseInsensitiveContains(query) }
        return newestFirst ? titles : Array(titles.reversed())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.md) {
            HStack {
                WorkspaceHeader(title: "Recordings", subtitle: "Open and edit recordings stored on this Mac.", icon: "film-strip")
                Spacer(minLength: 0)
                IconButton("arrow-clockwise", label: "Refresh recordings", size: DS.xl, action: reload)
                    .disabled(loading && !previewOnly)
                RecordingAction(title: "Record Screen", icon: "circle", action: record)
            }
            if !files.isEmpty || !fixtures.isEmpty {
                HStack(spacing: DS.sm) {
                    Icon("magnifying-glass", size: DS.icon).foregroundStyle(.secondary)
                    TextField("Find a recording", text: $query)
                        .textFieldStyle(.plain)
                        .font(DS.body)
                    if !query.isEmpty {
                        IconButton("x", label: "Clear recording search", size: DS.xl) { query = "" }
                    }
                    Picker("Sort recordings", selection: $newestFirst) {
                        Text("Newest first").tag(true)
                        Text("Oldest first").tag(false)
                    }.labelsHidden().fixedSize().font(DS.body)
                }
                .padding(DS.sm)
                .modifier(GlassSurface(radius: DS.smallRadius))
            }
            libraryContent
        }
        .padding(DS.lg)
        .padding(.top, DS.lg)
        .background(WorkspaceBackground())
        .task(id: refresh) {
            if !previewOnly {
                do {
                    let found = try await Task.detached(priority: .userInitiated) { try archive.recordings() }.value
                    try Task.checkCancellation()
                    files = found
                    message = nil
                } catch is CancellationError { return }
                catch { message = error.localizedDescription }
            }
            loading = false
        }
    }

    private func reload() {
        loading = true
        refresh &+= 1
    }

    @ViewBuilder private var libraryContent: some View {
        if let message {
            VStack(alignment: .leading, spacing: DS.sm) {
                Text("Couldn’t open recordings").font(DS.emphasis)
                Text(message).font(DS.body).foregroundStyle(.secondary).textSelection(.enabled)
                Button("Retry", action: reload).buttonStyle(QuietButtonStyle())
            }
            .padding(DS.md)
            .modifier(GlassSurface(radius: DS.groupRadius))
            Spacer(minLength: 0)
        } else if loading && !previewOnly && files.isEmpty {
            ProgressView().controlSize(.small).accessibilityLabel("Loading recordings")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if matchingFiles.isEmpty {
            VStack(spacing: DS.sm) {
                Icon(files.isEmpty ? "film-strip" : "magnifying-glass", size: DS.xl)
                    .foregroundStyle(DS.actionInk(scheme))
                    .frame(width: DS.xxl + DS.sm, height: DS.xxl + DS.sm)
                    .modifier(GlassSurface(radius: DS.smallRadius))
                    .accessibilityHidden(true)
                Text(files.isEmpty ? "No recordings yet" : "No matching recordings").font(DS.emphasis)
                Text(files.isEmpty ? "Start a screen recording to save it here." : "Search by part of the recording’s filename.")
                    .font(DS.body).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(GlassSurface(radius: DS.groupRadius))
        } else {
            ScrollView {
                LazyVStack(spacing: DS.sm) {
                    ForEach(matchingFiles, id: \.self) { url in
                        RecordingFileRow(url: url, sampleImage: fixtures[url], open: { open(url) })
                    }
                }.padding(DS.xs)
            }
        }
    }
}

private struct RecordingFileRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @LocalState private var image: CGImage?
    @LocalState private var info: RecordingMediaInfo?
    let url: URL
    var sampleImage: CGImage?
    let open: () -> Void

    private var title: String { url.deletingPathExtension().lastPathComponent }

    var body: some View {
        Button(action: open) {
            HStack(spacing: DS.md) {
                ZStack {
                    DS.black
                    if let image = sampleImage ?? image { Image(decorative: image, scale: 1).resizable().scaledToFit() }
                    else { Icon("monitor", size: DS.lg).foregroundStyle(DS.white) }
                }
                .frame(width: DS.xxl * 2, height: DS.xxl + DS.xs)
                .clipShape(RoundedRectangle(cornerRadius: DS.controlRadius, style: .continuous))
                VStack(alignment: .leading, spacing: DS.xs) {
                    Text(title).font(DS.emphasis).lineLimit(1)
                    if let info {
                        Text("\(recordingTimeCode(info.range.duration)) · \(Int(info.pixelSize.width)) × \(Int(info.pixelSize.height))")
                            .font(DS.mono).foregroundStyle(.secondary)
                            .transition(.opacity)
                    } else if sampleImage != nil {
                        Text("0:24 · Screen recording").font(DS.mono).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Icon("caret-right", size: DS.icon).foregroundStyle(.secondary).accessibilityHidden(true)
            }
            .padding(DS.sm)
            .modifier(GlassSurface(radius: DS.smallRadius, interactive: true))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Open \(title)")
        .contextMenu {
            Button("Open in Recording Editor", action: open)
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
        .task(id: url) {
            guard sampleImage == nil, let info = try? await RecordingMedia.inspect(url), !Task.isCancelled else { return }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.maximumSize = CGSize(width: 160, height: 90)
            generator.appliesPreferredTrackTransform = true
            let frame = try? await generator.image(at: CMTime(seconds: info.range.start, preferredTimescale: 6000))
            guard !Task.isCancelled else { return }
            withAnimation(DS.Motion.gentle(reduceMotion)) {
                self.info = info
                image = frame?.image
            }
        }
    }
}

@MainActor enum RecordingPreview {
    static func setup(allowed: Bool = true, mode: RecordingSetup.Mode = .display, example: CGImage? = nil) -> some View {
        let model = RecordingSetup()
        model.mode = mode
        model.displays = [
            RecordingChoice(id: 1, name: "Built-in Display", frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                            pixelSize: CGSize(width: 3024, height: 1964)),
            RecordingChoice(id: 2, name: "External Display", frame: CGRect(x: 1512, y: 220, width: 1920, height: 1080),
                            pixelSize: CGSize(width: 3840, height: 2160))
        ]
        model.windows = [
            RecordingChoice(id: 3, name: "Notes — Capture ideas", frame: CGRect(x: 80, y: 80, width: 1080, height: 760)),
            RecordingChoice(id: 4, name: "Finder — Projects", frame: CGRect(x: 201, y: 145, width: 920, height: 690))
        ]
        model.displayID = 1
        model.windowID = 3
        if mode == .area { model.area = CGRect(x: 120, y: 160, width: 1100, height: 650) }
        model.preview = example
        model.options.systemAudio = true
        if mode == .window {
            model.options.camera = true
            model.cameraLayout = .circle
        }
        return RecordingSetupView(model: model, permission: ScreenPermission(check: { allowed }, request: { false }),
                                  loadWindows: {}, openPrivacy: {}, record: {})
    }

    static func controls() -> some View {
        let model = RecordingSetup()
        model.displays = [RecordingChoice(id: 1, name: "Built-in Display")]
        model.displayID = 1
        model.phase = .recording
        model.startedAt = .now.addingTimeInterval(-18)
        return RecordingControls(model: model, stop: {})
    }

    static func editor(image: CGImage, showsTranscript: Bool = false, showsMarkup: Bool = false, showsCamera: Bool = false,
                       showsAsk: Bool = false) -> some View {
        let pane: RecordingEditorView.Inspector
        if showsAsk { pane = .ask }
        else if showsMarkup { pane = .markup }
        else if showsCamera { pane = .camera }
        else if showsTranscript { pane = .transcript }
        else { pane = .edit }
        let options = AskOptions()
        return RecordingEditorView(model: .fixture(image, showsTranscript: showsTranscript, showsMarkup: showsMarkup,
                                                   showsCamera: showsCamera, askOptions: options),
                                   export: { _ in }, previewAskOptions: options, activeInspector: pane)
    }

    static func library(image: CGImage? = nil) -> some View {
        let previews = image.map { image in
            Dictionary(uniqueKeysWithValues: ["Website walkthrough", "Settings walkthrough", "Project review"].map {
                (URL(filePath: "/preview/\($0).mp4"), image)
            })
        } ?? [:]
        return RecordingLibraryView(archive: RecordingArchive(folder: .temporaryDirectory.appending(path: UUID().uuidString)),
                                    open: { _ in }, record: {}, fixtures: previews, previewOnly: true)
    }
}
