import AVFoundation
import CoreMedia
import Foundation
import os

public enum CameraRecordingError: Equatable, LocalizedError, Sendable {
    case permission, unavailable, alreadyStarted, timedOut, noVideo, noOverlap, destinationInUse

    public var errorDescription: String? {
        switch self {
        case .permission: "Allow camera access in System Settings, or record with the camera off."
        case .unavailable: "SuperShot couldn’t start the camera. Check that a camera is connected."
        case .alreadyStarted: "This camera session has already started."
        case .timedOut: "The camera stopped responding."
        case .noVideo: "The camera didn’t save a video track."
        case .noOverlap: "The camera track couldn’t be aligned with the screen recording."
        case .destinationInUse: "A camera track already exists for this recording."
        }
    }
}

/// A completed camera recording awaiting alignment and final storage.
public struct CameraRecording: Sendable {
    let temporaryFolder: URL
    let video: URL
    let startedAt: CMTime

    public func discard() {
        try? FileManager.default.removeItem(at: temporaryFolder)
    }

    /// Saves a silent MP4 starting at the screen recording's start time.
    /// The capture file keeps its original pixels and audio.
    public func persist(for screenURL: URL, screenStartedAt: CMTime) async throws -> URL {
        defer { discard() }
        let destination = RecordingCamera.sidecarURL(for: screenURL)
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: destination.path) else { throw CameraRecordingError.destinationInUse }

        let camera = AVURLAsset(url: video)
        let screen = AVURLAsset(url: screenURL)
        guard let cameraTrack = try await camera.loadTracks(withMediaType: .video).first,
              let screenTrack = try await screen.loadTracks(withMediaType: .video).first else {
            throw CameraRecordingError.noVideo
        }
        let (cameraTime, orientation) = try await cameraTrack.load(.timeRange, .preferredTransform)
        let screenTime = try await screenTrack.load(.timeRange)
        let range = try Self.alignedRange(cameraStartedAt: startedAt, screenStartedAt: screenStartedAt,
                                         cameraDuration: cameraTime.duration, screenDuration: screenTime.duration)
        let videoOnly = AVMutableComposition()
        guard let outputTrack = videoOnly.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw CameraRecordingError.noVideo
        }
        try outputTrack.insertTimeRange(CMTimeRange(start: cameraTime.start + range.start, duration: range.duration),
                                        of: cameraTrack, at: .zero)
        outputTrack.preferredTransform = orientation
        guard let session = AVAssetExportSession(asset: videoOnly, presetName: AVAssetExportPresetHighestQuality) else {
            throw CameraRecordingError.noVideo
        }
        let folder = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        let staged = folder.appending(path: ".\(UUID().uuidString).mp4")
        defer { try? fileManager.removeItem(at: staged) }
        try await session.export(to: staged, as: .mp4)
        try Task.checkCancellation()
        try fileManager.moveItem(at: staged, to: destination)
        return destination
    }

    static func alignedRange(cameraStartedAt: CMTime, screenStartedAt: CMTime,
                             cameraDuration: CMTime, screenDuration: CMTime) throws -> CMTimeRange {
        guard [cameraStartedAt, screenStartedAt, cameraDuration, screenDuration].allSatisfy(\.isNumeric),
              cameraStartedAt.epoch == screenStartedAt.epoch,
              cameraDuration > .zero, screenDuration > .zero else { throw CameraRecordingError.noOverlap }
        let preRoll = screenStartedAt - cameraStartedAt
        let duration = min(screenDuration, cameraDuration - preRoll)
        guard preRoll >= .zero, duration > .zero else { throw CameraRecordingError.noOverlap }
        return CMTimeRange(start: preRoll, duration: duration)
    }
}

/// A one-shot local camera session. The caller starts it only after the user chooses to record with the camera.
@MainActor public final class RecordingCamera {
    public typealias Clip = CameraRecording
    private var attempted = false
    private var driver: CaptureDriver?
    private var temporaryFolder: URL?
    private var startedAt: CMTime?
    private var startWaiter: CheckedContinuation<Void, any Error>?
    private var stopWaiters: [CheckedContinuation<Clip, any Error>] = []
    private var completion: Result<Clip, any Error>?
    private var timeout: Task<Void, Never>?

    nonisolated public static var clock: CMTime {
        CMClockGetTime(CMClockGetHostTimeClock())
    }

    nonisolated public static func sidecarURL(for screenURL: URL) -> URL {
        screenURL.deletingLastPathComponent()
            .appending(path: "Camera Tracks", directoryHint: .isDirectory)
            .appending(path: screenURL.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("mp4")
    }

    public init() {}

    public func start() async throws {
        guard !attempted, completion == nil else { throw CameraRecordingError.alreadyStarted }
        attempted = true
        let allowed = await AVCaptureDevice.requestAccess(for: .video)
        try Task.checkCancellation()
        guard completion == nil else { throw CancellationError() }
        guard allowed else { throw CameraRecordingError.permission }
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "SuperShot-Camera-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        temporaryFolder = folder
        let driver = CaptureDriver { [weak self] event in
            Task { @MainActor in self?.receive(event) }
        }
        self.driver = driver
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                startWaiter = continuation
                armTimeout()
                driver.start(to: folder.appending(path: "Camera.mov"))
            }
        } onCancel: {
            Task { @MainActor [weak self] in await self?.discard() }
        }
    }

    public func finish() async throws -> Clip {
        if let completion { return try completion.get() }
        guard startedAt != nil, let driver else { throw CameraRecordingError.noVideo }
        return try await withCheckedThrowingContinuation { continuation in
            let stopRequested = !stopWaiters.isEmpty
            stopWaiters.append(continuation)
            if !stopRequested {
                armTimeout()
                driver.stop()
            }
        }
    }

    public func discard() async {
        if startedAt != nil {
            let clip = try? await finish()
            clip?.discard()
        } else {
            complete(.failure(CancellationError()))
        }
    }

    private func receive(_ event: CaptureDriver.Event) {
        guard completion == nil else { return }
        switch event {
        case let .started(time):
            startedAt = time
            timeout?.cancel()
            startWaiter?.resume()
            startWaiter = nil
        case let .finished(url):
            guard let temporaryFolder, let startedAt else {
                complete(.failure(CameraRecordingError.noVideo))
                return
            }
            complete(.success(Clip(temporaryFolder: temporaryFolder, video: url, startedAt: startedAt)))
        case let .failed(error):
            complete(.failure(error))
        }
    }

    private func armTimeout() {
        timeout?.cancel()
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(12)) }
            catch { return }
            self?.complete(.failure(CameraRecordingError.timedOut))
        }
    }

    private func complete(_ result: Result<Clip, any Error>) {
        guard completion == nil else { return }
        completion = result
        timeout?.cancel()
        timeout = nil
        let abandonedFolder: URL?
        let startError: any Error
        switch result {
        case .success:
            abandonedFolder = nil
            startError = CameraRecordingError.noVideo
        case let .failure(error):
            abandonedFolder = temporaryFolder
            startError = error
        }
        driver?.release(remove: abandonedFolder)
        driver = nil
        startWaiter?.resume(throwing: startError)
        startWaiter = nil
        for waiter in stopWaiters { waiter.resume(with: result) }
        stopWaiters.removeAll()
    }
}

/// AVFoundation session operations are serialized on a dedicated queue because they can block.
private final class CaptureDriver: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    enum Event: Sendable { case started(CMTime), finished(URL), failed(any Error) }

    private let queue = DispatchQueue(label: "SuperShot.CameraCapture")
    private let released = OSAllocatedUnfairLock(initialState: false)
    private var session: AVCaptureSession?
    private var output: AVCaptureMovieFileOutput?
    private let notify: @Sendable (Event) -> Void

    init(notify: @escaping @Sendable (Event) -> Void) { self.notify = notify }

    func start(to url: URL) {
        queue.async {
            do {
                guard !self.released.withLock({ $0 }), let camera = AVCaptureDevice.default(for: .video) else {
                    throw CameraRecordingError.unavailable
                }
                let input = try AVCaptureDeviceInput(device: camera)
                let session = AVCaptureSession()
                let output = AVCaptureMovieFileOutput()
                do {
                    session.beginConfiguration()
                    defer { session.commitConfiguration() }
                    guard session.canAddInput(input) else { throw CameraRecordingError.unavailable }
                    session.addInput(input)
                    if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
                    guard session.canAddOutput(output) else { throw CameraRecordingError.unavailable }
                    session.addOutput(output)
                }
                self.session = session
                self.output = output
                guard !self.released.withLock({ $0 }) else { return }
                session.startRunning()
                guard session.isRunning, output.connection(with: .video) != nil else {
                    throw CameraRecordingError.unavailable
                }
                guard !self.released.withLock({ $0 }) else { return }
                output.startRecording(to: url, recordingDelegate: self)
            } catch { self.notify(.failed(error)) }
        }
    }

    func stop() {
        queue.async {
            if self.output?.isRecording == true { self.output?.stopRecording() }
        }
    }

    func release(remove folder: URL?) {
        released.withLock { $0 = true }
        queue.async {
            if self.output?.isRecording == true { self.output?.stopRecording() }
            self.session?.stopRunning()
            self.session = nil
            self.output = nil
            if let folder { try? FileManager.default.removeItem(at: folder) }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL,
                    startPTS: CMTime, from connections: [AVCaptureConnection]) {
        let fallback = RecordingCamera.clock
        queue.async {
            // Use the first camera sample's time in the same host clock the screen recorder uses.
            let hostTime = self.session?.synchronizationClock.map {
                CMSyncConvertTime(startPTS, from: $0, to: CMClockGetHostTimeClock())
            }
            self.notify(.started(hostTime.flatMap { $0.isNumeric ? $0 : nil } ?? fallback))
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: (any Error)?) {
        if let error, (error as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool != true {
            notify(.failed(error))
        } else {
            notify(.finished(outputFileURL))
        }
    }
}
