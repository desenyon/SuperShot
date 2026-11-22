import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import ScreenCaptureKit

public enum RecordingFailure: Equatable, LocalizedError, Sendable {
    case microphoneAccess, missingMicrophone, missingSource, invalidDimensions, unsupportedFormat, timedOut, empty, invalidRange, invalidDestination, gifTooLong, exportUnavailable

    public var errorDescription: String? {
        switch self {
        case .microphoneAccess: "Allow microphone access in System Settings, or record with the microphone off."
        case .missingMicrophone: "That microphone was disconnected. Choose an available microphone and try again."
        case .missingSource: "The screen or window is no longer available. Choose a recording source and try again."
        case .invalidDimensions: "The selected capture area is too small to record."
        case .unsupportedFormat: "macOS could not start an MP4 recording on this Mac."
        case .timedOut: "Screen recording stopped responding. Start a new recording to try again."
        case .empty: "This recording has no video. Try recording for at least a second."
        case .invalidRange: "Keep at least one frame in the timeline before exporting."
        case .invalidDestination: "Choose a different destination to preserve the original recording."
        case .gifTooLong: "Trim the clip to 30 seconds or less for an animated GIF."
        case .exportUnavailable: "This recording could not be exported in the selected format."
        }
    }
}

public enum RecordingSource: Equatable, Sendable {
    case display(CGDirectDisplayID)
    case window(CGWindowID)
    /// An area in display-local points, measured from the top left.
    case area(CGDirectDisplayID, CGRect)
}

public enum RecordingResolution: String, CaseIterable, Sendable {
    case automatic, fullHD, hd

    public var title: String {
        switch self { case .automatic: "Up to 4K"; case .fullHD: "Up to 1080p"; case .hd: "Up to 720p" }
    }

    var maximum: CGSize {
        switch self {
        case .automatic: CGSize(width: 3840, height: 2160)
        case .fullHD: CGSize(width: 1920, height: 1080)
        case .hd: CGSize(width: 1280, height: 720)
        }
    }
}

public enum RecordingFrameRate: Int, CaseIterable, Sendable {
    case fps30 = 30
    case fps60 = 60
}

public struct RecordingOptions: Equatable, Sendable {
    public var showCursor: Bool
    public var showClicks: Bool
    public var systemAudio: Bool
    public var microphone: Bool
    public var zoomOnClicks: Bool
    public var camera: Bool
    public var resolution: RecordingResolution
    public var frameRate: RecordingFrameRate
    public var microphoneDeviceID: String?

    public init(showCursor: Bool = true, showClicks: Bool = false, systemAudio: Bool = false, microphone: Bool = false,
                zoomOnClicks: Bool = false, camera: Bool = false, resolution: RecordingResolution = .automatic,
                frameRate: RecordingFrameRate = .fps30, microphoneDeviceID: String? = nil) {
        self.showCursor = showCursor
        self.showClicks = showClicks
        self.systemAudio = systemAudio
        self.microphone = microphone
        self.zoomOnClicks = zoomOnClicks
        self.camera = camera
        self.resolution = resolution
        self.frameRate = frameRate
        self.microphoneDeviceID = microphoneDeviceID
    }
}

struct RecordingDimensions: Equatable {
    let width: Int
    let height: Int

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    init?(pixels: CGSize, resolution: RecordingResolution = .automatic) {
        guard pixels.width.isFinite, pixels.height.isFinite, pixels.width >= 2, pixels.height >= 2 else { return nil }
        let landscape = resolution.maximum
        let maximum = resolution == .automatic || pixels.width >= pixels.height
            ? landscape
            : CGSize(width: landscape.height, height: landscape.width)
        let scale = min(1, maximum.width / pixels.width, maximum.height / pixels.height)
        let width = Int(pixels.width * scale / 2) * 2
        let height = Int(pixels.height * scale / 2) * 2
        guard width >= 2, height >= 2 else { return nil }
        self.init(width: width, height: height)
    }
}

@MainActor private struct RecordingTarget {
    let filter: SCContentFilter
    let crop: CGRect?

    var points: CGSize { crop?.size ?? filter.contentRect.size }

    static func resolve(_ source: RecordingSource) async throws -> Self {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        switch source {
        case .display(let id):
            return Self(filter: try filter(id, content), crop: nil)
        case .area(let id, let rect):
            let filter = try filter(id, content)
            guard let crop = RecordingSourceGeometry.crop(rect, on: filter.contentRect) else {
                throw RecordingFailure.invalidDimensions
            }
            return Self(filter: filter, crop: crop)
        case .window(let id):
            guard let window = content.windows.first(where: { $0.windowID == id }),
                  window.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier else {
                throw RecordingFailure.missingSource
            }
            return Self(filter: SCContentFilter(desktopIndependentWindow: window), crop: nil)
        }
    }

    private static func filter(_ id: CGDirectDisplayID, _ content: SCShareableContent) throws -> SCContentFilter {
        guard let display = content.displays.first(where: { $0.displayID == id }) else { throw RecordingFailure.missingSource }
        let excluded = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        return SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
    }
}

/// A single recording session. ScreenCaptureKit's output callback marks when the file is complete.
@MainActor public final class ScreenRecordingSession {
    public let outputURL: URL
    public private(set) var startedAtHostTime: CMTime?
    public var onEnd: (() -> Void)?
    private var stream: SCStream?
    private var recording: SCRecordingOutput?
    private var observer: Observer?
    private var started = false
    private var startWaiter: CheckedContinuation<Void, any Error>?
    private var finishWaiters: [CheckedContinuation<URL, any Error>] = []
    private var completion: Result<URL, any Error>?
    private var timeout: Task<Void, Never>?
    private var stopping = false

    public init(outputURL: URL) { self.outputURL = outputURL }

    public static func sourcePreview(_ source: RecordingSource) async throws -> CGImage {
        let target = try await RecordingTarget.resolve(source)
        guard let size = RecordingSourceGeometry.previewPixels(for: target.points) else { throw RecordingFailure.invalidDimensions }
        let configuration = SCStreamConfiguration()
        configuration.width = Int(size.width)
        configuration.height = Int(size.height)
        if let crop = target.crop { configuration.sourceRect = crop }
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        return try await SCScreenshotManager.captureImage(contentFilter: target.filter, configuration: configuration)
    }

    public func start(source: RecordingSource, options: RecordingOptions) async throws {
        let target = try await RecordingTarget.resolve(source)
        let scale = CGFloat(target.filter.pointPixelScale)
        guard let dimensions = RecordingDimensions(pixels: CGSize(width: target.points.width * scale,
                                                                    height: target.points.height * scale),
                                                   resolution: options.resolution) else {
            throw RecordingFailure.invalidDimensions
        }
        let config = SCStreamConfiguration()
        config.width = dimensions.width
        config.height = dimensions.height
        if let crop = target.crop { config.sourceRect = crop }
        config.minimumFrameInterval = CMTime(value: 1, timescale: Int32(options.frameRate.rawValue))
        config.showsCursor = options.showCursor
        config.showMouseClicks = options.showClicks
        if options.showClicks { config.pixelFormat = kCVPixelFormatType_32BGRA }
        config.capturesAudio = options.systemAudio
        config.excludesCurrentProcessAudio = true
        config.captureMicrophone = options.microphone
        if options.microphone { config.microphoneCaptureDeviceID = options.microphoneDeviceID }
        config.ignoreShadowsSingleWindow = true
        config.streamName = "SuperShot Recording"
        let output = SCRecordingOutputConfiguration()
        guard output.availableOutputFileTypes.contains(.mp4), output.availableVideoCodecTypes.contains(.h264) else {
            throw RecordingFailure.unsupportedFormat
        }
        output.outputURL = outputURL
        output.outputFileType = .mp4
        output.videoCodecType = .h264
        if #available(macOS 27, *) { output.mixesAudioWithMicrophone = false }

        let observer = Observer { [weak self] event in
            Task { @MainActor in self?.receive(event) }
        }
        let stream = SCStream(filter: target.filter, configuration: config, delegate: observer)
        let recording = SCRecordingOutput(configuration: output, delegate: observer)
        try stream.addRecordingOutput(recording)
        self.observer = observer
        self.stream = stream
        self.recording = recording
        startTimeout()
        Task { [self] in
            do {
                try await stream.startCapture()
                if self.stream == nil {
                    try? await stream.stopCapture()
                    // The caller may have cleaned up the staging file before macOS opened it.
                    if !started { try? FileManager.default.removeItem(at: outputURL) }
                }
            }
            catch { complete(.failure(error)) }
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { startWaiter = $0 }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, !started else { return }
                complete(.failure(CancellationError()))
            }
        }
    }

    public func finish() async throws -> URL {
        if !stopping, completion == nil, let stream {
            stopping = true
            startTimeout()
            Task { [weak self] in
                do { try await stream.stopCapture() }
                catch { self?.complete(.failure(error)) }
            }
        }
        if let completion { return try completion.get() }
        guard stream != nil else { throw RecordingFailure.empty }
        return try await withCheckedThrowingContinuation { finishWaiters.append($0) }
    }

    private func receive(_ event: Event) {
        guard completion == nil else { return }
        switch event {
        case .started(let hostTime):
            started = true
            startedAtHostTime = hostTime
            if !stopping { timeout?.cancel() }
            startWaiter?.resume()
            startWaiter = nil
        case .finished: complete(.success(outputURL))
        case .failed(let error): complete(.failure(error))
        }
    }

    private func startTimeout() {
        timeout?.cancel()
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(12)) }
            catch { return }
            self?.complete(.failure(RecordingFailure.timedOut))
        }
    }

    private func complete(_ result: Result<URL, any Error>) {
        guard completion == nil else { return }
        completion = result
        timeout?.cancel()
        timeout = nil
        if let startWaiter {
            switch result {
            case .success: startWaiter.resume(throwing: RecordingFailure.empty)
            case .failure(let error): startWaiter.resume(throwing: error)
            }
        }
        startWaiter = nil
        for waiter in finishWaiters { waiter.resume(with: result) }
        finishWaiters.removeAll()
        if !stopping && started { onEnd?() }
        // Recording-output failures can end the writer before the stream stops.
        if !stopping, let stream { Task { try? await stream.stopCapture() } }
        stream = nil
        recording = nil
        observer = nil
    }

    private enum Event: Sendable {
        case started(CMTime), finished, failed(any Error)
    }

    private final class Observer: NSObject, SCStreamDelegate, SCRecordingOutputDelegate {
        let notify: @Sendable (Event) -> Void
        init(notify: @escaping @Sendable (Event) -> Void) { self.notify = notify }
        func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
            notify(.started(CMClockGetTime(CMClockGetHostTimeClock())))
        }
        func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) { notify(.finished) }
        func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) { notify(.failed(error)) }
        func stream(_ stream: SCStream, didStopWithError error: any Error) { notify(.failed(error)) }
    }
}
