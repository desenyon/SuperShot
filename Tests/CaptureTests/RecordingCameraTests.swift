import AVFoundation
import CoreMedia
import CoreImage
import CoreVideo
import Foundation
import Testing
@testable import Capture

struct RecordingCameraTests {
    @Test func alignmentRemovesTheCameraPreRollAndStopsWithTheScreen() throws {
        let range = try CameraRecording.alignedRange(
            cameraStartedAt: seconds(5), screenStartedAt: seconds(5.5),
            cameraDuration: seconds(6), screenDuration: seconds(4)
        )
        #expect(range.start == seconds(0.5))
        #expect(range.duration == seconds(4))
    }

    @Test func shortCameraTrackEndsBeforeTheScreen() throws {
        let range = try CameraRecording.alignedRange(
            cameraStartedAt: seconds(5), screenStartedAt: seconds(5.5),
            cameraDuration: seconds(2), screenDuration: seconds(4)
        )
        #expect(range.start == seconds(0.5))
        #expect(range.duration == seconds(1.5))
    }

    @Test func invalidCaptureTimesCantProduceASidecarStartingAtTheWrongTime() {
        #expect(throws: CameraRecordingError.noOverlap) {
            try CameraRecording.alignedRange(
                cameraStartedAt: seconds(9), screenStartedAt: seconds(5.5),
                cameraDuration: seconds(2), screenDuration: seconds(4)
            )
        }
        #expect(throws: CameraRecordingError.noOverlap) {
            try CameraRecording.alignedRange(
                cameraStartedAt: seconds(0), screenStartedAt: seconds(5),
                cameraDuration: seconds(2), screenDuration: seconds(4)
            )
        }
        #expect(throws: CameraRecordingError.noOverlap) {
            try CameraRecording.alignedRange(
                cameraStartedAt: .indefinite, screenStartedAt: seconds(5),
                cameraDuration: seconds(2), screenDuration: seconds(4)
            )
        }
    }

    @Test func generatedMoviesProduceAnAlignedSidecarWithoutChangingTheScreenFile() async throws {
        let base = try makeFolder()
        defer { try? FileManager.default.removeItem(at: base) }
        let staging = base.appending(path: "staging", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        let source = staging.appending(path: "Camera.mov")
        let screen = base.appending(path: "Screen.mp4")
        try await synthesizeMovie(at: source, format: .mov, frameCount: 20)
        try await synthesizeMovie(at: screen, format: .mp4, frameCount: 10)
        let screenBefore = try Data(contentsOf: screen)

        let camera = CameraRecording(temporaryFolder: staging, video: source, startedAt: seconds(5))
        let result = try await camera.persist(for: screen, screenStartedAt: seconds(5.5))
        #expect(result.path == base.appending(path: "Camera Tracks/Screen.mp4").path)
        #expect(try Data(contentsOf: screen) == screenBefore)
        #expect(!FileManager.default.fileExists(atPath: staging.path))

        let sidecar = AVURLAsset(url: result)
        let duration = try await sidecar.load(.duration)
        #expect(abs(duration.seconds - 1) <= 0.1)
        #expect(try await sidecar.loadTracks(withMediaType: .audio).isEmpty)
        #expect(try await sidecar.loadTracks(withMediaType: .video).count == 1)
    }

    @Test func persistingCameraPreservesAnExistingSidecar() async throws {
        let base = try makeFolder()
        defer { try? FileManager.default.removeItem(at: base) }
        let staging = base.appending(path: "staging", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        let source = staging.appending(path: "Camera.mov")
        try Data([1]).write(to: source)
        let screen = base.appending(path: "Screen.mp4")
        let existing = RecordingCamera.sidecarURL(for: screen)
        try FileManager.default.createDirectory(at: existing.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([2, 3]).write(to: existing)

        let camera = CameraRecording(temporaryFolder: staging, video: source, startedAt: seconds(5))
        await #expect(throws: CameraRecordingError.destinationInUse) {
            try await camera.persist(for: screen, screenStartedAt: seconds(5.5))
        }
        #expect(try Data(contentsOf: existing) == Data([2, 3]))
        #expect(!FileManager.default.fileExists(atPath: staging.path))
    }

    @Test func cameraCompositionFollowsTheSameCutsAndRendersInTheChosenCorner() async throws {
        let base = try makeFolder()
        defer { try? FileManager.default.removeItem(at: base) }
        let screen = base.appending(path: "Screen.mp4")
        let sidecar = RecordingCamera.sidecarURL(for: screen)
        try FileManager.default.createDirectory(at: sidecar.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await synthesizeMovie(at: screen, format: .mp4, frameCount: 20, shade: 32)
        try await synthesizeMovie(at: sidecar, format: .mp4, frameCount: 13, shade: 210)

        let composition = AVMutableComposition()
        let oldVideo = AVURLAsset(url: screen)
        let source = try #require(try await oldVideo.loadTracks(withMediaType: .video).first)
        let screenTrack = try #require(composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
        let cuts = [
            CMTimeRange(start: seconds(0.3), duration: seconds(0.4)),
            CMTimeRange(start: seconds(1.1), duration: seconds(0.6))
        ]
        try screenTrack.insertTimeRange(cuts[0], of: source, at: .zero)
        try screenTrack.insertTimeRange(cuts[1], of: source, at: seconds(0.4))
        let camera = try #require(try await RecordingCameraComposition.insertCamera(from: screen, into: composition,
                                                                                     kept: cuts, screenStart: .zero))
        let segments = try await camera.load(.segments)
        #expect(segments.count == 2)
        #expect(segments[0].timeMapping.source == cuts[0])
        #expect(segments[1].timeMapping.source.start == seconds(1.1))
        #expect(segments[1].timeMapping.source.end == seconds(1.3))
        #expect(segments[1].timeMapping.target.start == seconds(0.4))

        let video = try await RecordingCameraComposition.make(
            screen: screenTrack, camera: camera, renderSize: CGSize(width: 96, height: 64),
            duration: seconds(1), layout: .bottomRight,
            renderScreen: { image, _ in image }
        )
        let generator = AVAssetImageGenerator(asset: composition)
        generator.videoComposition = video
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let composed = try await generator.image(at: seconds(0.5)).image
        #expect(composed.width == 96)
        #expect(luminance(of: composed, x: 20, y: 20) < 64)
        #expect(luminance(of: composed, x: 82, y: 53) > 180)
        let afterCameraStops = try await generator.image(at: seconds(0.8)).image
        #expect(luminance(of: afterCameraStops, x: 82, y: 53) < 64)

        let exportedURL = base.appending(path: "Composed.mp4")
        let exporter = try #require(AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality))
        exporter.videoComposition = video
        try await exporter.export(to: exportedURL, as: .mp4)
        let exported = AVURLAsset(url: exportedURL)
        let duration = try await exported.load(.duration)
        #expect(abs(duration.seconds - 1) <= 1 / 30)
        let exportedFrame = try await AVAssetImageGenerator(asset: exported).image(at: seconds(0.3)).image
        #expect(luminance(of: exportedFrame, x: 82, y: 53) > 180)

        for (layout, cameraPoint) in [(RecordingCameraLayout.bottomLeft, (13, 53)), (.topLeft, (13, 10)), (.topRight, (82, 10)),
                                      (.circle, (84, 52)), (.split, (82, 32)), (.stacked, (48, 53)), (.cameraOnly, (48, 32))] {
            generator.videoComposition = try await RecordingCameraComposition.make(
                screen: screenTrack, camera: camera, renderSize: CGSize(width: 96, height: 64),
                duration: seconds(1), layout: layout, renderScreen: { image, _ in image }
            )
            let changed = try await generator.image(at: seconds(0.5)).image
            #expect(luminance(of: changed, x: cameraPoint.0, y: cameraPoint.1) > 180)
        }
    }

    @Test func timedCameraLayoutsAndMarkupRenderAfterCuts() async throws {
        let base = try makeFolder()
        defer { try? FileManager.default.removeItem(at: base) }
        let screen = base.appending(path: "Screen.mp4")
        let sidecar = RecordingCamera.sidecarURL(for: screen)
        try FileManager.default.createDirectory(at: sidecar.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await synthesizeMovie(at: screen, format: .mp4, frameCount: 20, shade: 64)
        try await synthesizeMovie(at: sidecar, format: .mp4, frameCount: 20, shade: 220)
        var edits = RecordingEdits(trim: try #require(RecordingRange(start: 0, end: 2)))
        edits.cuts = [try #require(RecordingRange(start: 0.5, end: 1.2))]
        edits.cameraLayout = .hidden
        let cameraRange = try #require(RecordingRange(start: 1.3, end: 1.8))
        edits.cameraSegments = [RecordingCameraSegment(range: cameraRange, layout: .cameraOnly)]
        edits.annotations = [RecordingAnnotation(kind: .cover, range: cameraRange,
                                                 start: CGPoint(x: 0.1, y: 0.1), end: CGPoint(x: 0.4, y: 0.4))]

        let playback = try await RecordingMedia.playback(screen, edits: edits)
        let generator = AVAssetImageGenerator(asset: playback.asset)
        generator.videoComposition = playback.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let before = try await generator.image(at: seconds(0.3)).image
        let during = try await generator.image(at: seconds(0.7)).image
        let after = try await generator.image(at: seconds(1.2)).image
        #expect(luminance(of: before, x: 48, y: 32) < 100)
        #expect(luminance(of: during, x: 48, y: 32) > 180)
        #expect(luminance(of: during, x: 25, y: 15) < 24)
        #expect(luminance(of: after, x: 48, y: 32) < 100)
    }

    private func seconds(_ value: Double) -> CMTime {
        CMTime(seconds: value, preferredTimescale: 600)
    }

    private func makeFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func luminance(of image: CGImage, x: Int, y: Int) -> UInt8 {
        guard let sample = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else { return 0 }
        var value: UInt8 = 0
        withUnsafeMutableBytes(of: &value) { buffer in
            let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                    bytesPerRow: 1, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            context?.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return value
    }

    private func synthesizeMovie(at url: URL, format: AVFileType, frameCount: Int, shade: UInt8? = nil) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: format)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 96, AVVideoHeightKey: 64
        ])
        let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 96, kCVPixelBufferHeightKey as String: 64
        ])
        writer.add(input)
        try #require(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        let pool = try #require(adapter.pixelBufferPool)
        for frame in 0..<frameCount {
            for _ in 0..<100 where !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            try #require(input.isReadyForMoreMediaData)
            var allocated: CVPixelBuffer?
            try #require(CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &allocated) == kCVReturnSuccess)
            let buffer = try #require(allocated)
            CVPixelBufferLockBaseAddress(buffer, [])
            CVPixelBufferGetBaseAddress(buffer)?.initializeMemory(as: UInt8.self, repeating: shade ?? UInt8(frame * 8),
                                                                  count: CVPixelBufferGetDataSize(buffer))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            try #require(adapter.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 10)))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: Int64(frameCount), timescale: 10))
        await writer.finishWriting()
        try #require(writer.status == .completed)
    }
}
