import AVFoundation
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Testing
@testable import Capture

struct RecordingTests {
    @Test func recordingDimensionsPreserveAspectAndStayEven() {
        #expect(RecordingDimensions(pixels: CGSize(width: 5120, height: 2880)) == .init(width: 3840, height: 2160))
        #expect(RecordingDimensions(pixels: CGSize(width: 1801, height: 3001)) == .init(width: 1296, height: 2160))
        #expect(RecordingDimensions(pixels: CGSize(width: 1281, height: 721)) == .init(width: 1280, height: 720))
        #expect(RecordingDimensions(pixels: CGSize(width: CGFloat.infinity, height: 400)) == nil)
    }

    @Test func timelineClipsAndMergesCuts() throws {
        let timeline = try #require(RecordingRange(start: 2, end: 14))
        let cuts = try [(-1.0, 3.0), (6, 8), (7, 10), (12, 15)].map { start, end in
            try #require(RecordingRange(start: max(0, start), end: end))
        }
        #expect(timeline.excluding(cuts) == [RecordingRange(start: 3, end: 6), RecordingRange(start: 10, end: 12)].compactMap { $0 })
        #expect(timeline.excluding([timeline]).isEmpty)
        #expect(RecordingRange(start: .nan, end: 10) == nil)
        #expect(RecordingRange(start: 3, end: 3) == nil)
    }

    @Test func archiveListsOnlyCommittedRecordingsAndKeepsSameSecondCaptures() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = RecordingArchive(folder: directory)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let first = try archive.reserve()
        let second = try archive.reserve()
        try Data([1]).write(to: first)
        try Data([2]).write(to: second)
        #expect(try archive.recordings().isEmpty)
        let a = try archive.commit(first, at: date)
        let b = try archive.commit(second, at: date)
        #expect(a != b)
        let saved = try archive.recordings().map(\.lastPathComponent)
        #expect(Set(saved) == Set([a.lastPathComponent, b.lastPathComponent]))
        #expect(try Data(contentsOf: a) == Data([1]))
        #expect(try Data(contentsOf: b) == Data([2]))
    }

    @Test func trimmedRecordingExportsMP4AndAnimatedGIFWithoutTouchingOriginal() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "Source.mp4")
        let mp4 = directory.appending(path: "Edited.mp4")
        let gif = directory.appending(path: "Edited.gif")
        try await synthesizeMovie(at: source)
        let original = try Data(contentsOf: source)
        let info = try await RecordingMedia.inspect(source)
        #expect(info.range.duration == 2)
        #expect(info.pixelSize == CGSize(width: 96, height: 64))
        var edits = RecordingEdits(trim: try #require(RecordingRange(start: 0.25, end: 1.75)))
        edits.cuts = [try #require(RecordingRange(start: 0.75, end: 1.25))]
        edits.zooms = [RecordingZoom(range: try #require(RecordingRange(start: 0.25, end: 0.75)), center: CGPoint(x: 0.9, y: 0.2))]
        edits.perspective = .right
        edits.captionStyle = .lightText
        let captions = [RecordingCue(text: "Edited clip", range: try #require(RecordingRange(start: 0.25, end: 0.75)))]
        #expect(edits.editedTime(forSourceTime: 1.4).isApproximatelyEqual(to: 0.65))
        #expect(edits.sourceTime(forEditedTime: 0.65).isApproximatelyEqual(to: 1.4))

        try await RecordingMedia.export(source, to: mp4, format: .mp4, edits: edits, transcript: captions)
        try await RecordingMedia.export(source, to: gif, format: .gif, edits: edits, transcript: captions)
        let edited = try await RecordingMedia.inspect(mp4)
        #expect(edited.range.duration.isApproximatelyEqual(to: 1, tolerance: 1.0 / 30))
        #expect(edited.pixelSize == info.pixelSize)
        let animation = try #require(CGImageSourceCreateWithURL(gif as CFURL, nil))
        #expect(CGImageSourceGetCount(animation) == 12)
        #expect(CGImageSourceCreateImageAtIndex(animation, 11, nil) != nil)
        await #expect(throws: RecordingFailure.invalidDestination) {
            try await RecordingMedia.export(source, to: source, format: .mp4, edits: edits)
        }
        #expect(try Data(contentsOf: source) == original)
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)) == ["Source.mp4", "Edited.mp4", "Edited.gif"])
    }

    @Test func exportsProtectTheOriginalAndAssociatedFiles() throws {
        let folder = URL(filePath: "/var/tmp/SuperShot")
        let source = folder.appending(path: "Capture.mp4")
        for file in [source, RecordingMedia.editsURL(for: source), RecordingMedia.transcriptURL(for: source),
                     RecordingCamera.sidecarURL(for: source)] {
            #expect(throws: RecordingFailure.invalidDestination) {
                try RecordingMedia.validateDestination(file, source: source)
            }
        }
        try RecordingMedia.validateDestination(folder.appending(path: "Edited.mp4"), source: source)
    }

    @Test func transcriptFollowsTrimAndCutsWhenExportingSubtitles() throws {
        let cues = try [(2.2, 2.6, "Hello"), (2.7, 3.1, "Um,"), (3.5, 4.0, "& <welcome>")].map { start, end, text in
            RecordingCue(text: text, range: try #require(RecordingRange(start: start, end: end)))
        }
        var edits = RecordingEdits(trim: try #require(RecordingRange(start: 2, end: 5)))
        edits.cuts = [try #require(RecordingRange(start: 2.5, end: 3.5))]
        #expect(RecordingTranscript.fillerCuts(cues) == [cues[1].range])
        #expect(RecordingTranscript.activeCues(cues, in: edits).map(\.text) == ["Hello", "& <welcome>"])
        #expect(RecordingTranscript.contents(cues, in: edits, as: .srt) == "1\n00:00:00,200 --> 00:00:01,000\nHello & <welcome>\n")
        #expect(RecordingTranscript.contents(cues, in: edits, as: .vtt).contains("Hello &amp; &lt;welcome>"))
        let last = RecordingCue(text: "Next", range: try #require(RecordingRange(start: 6, end: 7)))
        #expect(RecordingTranscript.pauseCuts([cues[2], last]) == [RecordingRange(start: 4.12, end: 5.88)].compactMap { $0 })
    }

    @Test func clickZoomUsesDisplayCoordinatesAndIgnoresAdjacentClicks() throws {
        let display = CGRect(x: -200, y: 120, width: 200, height: 100)
        let point = CGPoint(x: -50, y: 145)
        let first = try #require(RecordingZoom.atClick(point, in: display, time: 1, after: nil))
        #expect(first.center == CGPoint(x: 0.75, y: 0.25))
        #expect(RecordingZoom.atClick(point, in: display, time: 1.1, after: first) == nil)
        #expect(RecordingZoom.atClick(.zero, in: display, time: 3, after: first) == nil)
        #expect(RecordingZoom.atClick(point, in: display, time: 3, after: first)?.range.start == 3)
    }

    @Test func exportedCameraLayoutUsesAlignedVideoOnEditedTimeline() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "Screen.mp4")
        let camera = RecordingCamera.sidecarURL(for: source)
        try FileManager.default.createDirectory(at: camera.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await synthesizeMovie(at: source, solidGray: 32)
        try await synthesizeMovie(at: camera, solidGray: 224)
        let info = try await RecordingMedia.inspect(source)
        #expect(info.hasCamera)
        var edits = RecordingEdits(trim: try #require(RecordingRange(start: 0.25, end: 1.75)))
        edits.cuts = [try #require(RecordingRange(start: 0.75, end: 1.25))]
        let result = directory.appending(path: "Composited.mp4")
        edits.cameraLayout = .bottomRight
        try await RecordingMedia.export(source, to: result, format: .mp4, edits: edits)
        let generated = AVAssetImageGenerator(asset: AVURLAsset(url: result))
        let image = try await generated.image(at: CMTime(value: 3, timescale: 4)).image
        let screenPixel = try grayscale(image, at: CGPoint(x: 30, y: 32))
        let cameraPixel = try grayscale(image, at: CGPoint(x: 83, y: 53))
        #expect(cameraPixel > 160)
        #expect(screenPixel < 80)
    }

    @Test func recordingAnnotationsFollowCutsInPlaybackAndBothExports() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "Source.mp4")
        try await synthesizeMovie(at: source, solidGray: 200)
        let original = try Data(contentsOf: source)
        var edits = RecordingEdits(trim: try #require(RecordingRange(start: 0, end: 2)))
        edits.cuts = [try #require(RecordingRange(start: 0.5, end: 1.2))]
        let first = RecordingAnnotation(kind: .cover, range: try #require(RecordingRange(start: 0.15, end: 0.5)),
                                        start: CGPoint(x: 0.1, y: 0.1), end: CGPoint(x: 0.4, y: 0.4))
        let removed = RecordingAnnotation(kind: .cover, range: try #require(RecordingRange(start: 0.7, end: 1)),
                                          start: CGPoint(x: 0.6, y: 0.1), end: CGPoint(x: 0.9, y: 0.4))
        edits.annotations = [first, removed]
        #expect(try JSONDecoder().decode(RecordingEdits.self, from: JSONEncoder().encode(edits)) == edits)
        let left = CGPoint(x: 25, y: 15)
        let right = CGPoint(x: 70, y: 15)
        let mp4 = directory.appending(path: "Edit.mp4")
        let gif = directory.appending(path: "Edit.gif")

        let playback = try await RecordingMedia.playback(source, edits: edits)
        let preview = AVAssetImageGenerator(asset: playback.asset)
        preview.videoComposition = playback.videoComposition
        preview.requestedTimeToleranceBefore = .zero
        preview.requestedTimeToleranceAfter = .zero
        let rendered = try await preview.image(at: CMTime(value: 1, timescale: 3)).image
        #expect(try grayscale(rendered, at: left) < 24)
        #expect(try grayscale(rendered, at: right) > 150)

        try await RecordingMedia.export(source, to: mp4, format: .mp4, edits: edits)
        try await RecordingMedia.export(source, to: gif, format: .gif, edits: edits)
        let export = AVAssetImageGenerator(asset: AVURLAsset(url: mp4))
        export.requestedTimeToleranceBefore = .zero
        export.requestedTimeToleranceAfter = .zero
        let movieFrame = try await export.image(at: CMTime(value: 1, timescale: 3)).image
        #expect(try grayscale(movieFrame, at: left) < 24)
        let animation = try #require(CGImageSourceCreateWithURL(gif as CFURL, nil))
        let early = try #require(CGImageSourceCreateImageAtIndex(animation, 4, nil))
        let late = try #require(CGImageSourceCreateImageAtIndex(animation, 11, nil))
        #expect(try grayscale(early, at: left) < 24)
        #expect(try grayscale(late, at: left) > 150)
        #expect(try grayscale(late, at: right) > 150)
        #expect(try Data(contentsOf: source) == original)
    }

    @Test func annotationRendererDrawsVectorAndFocusTools() throws {
        let bounds = CGRect(x: 0, y: 0, width: 128, height: 96)
        let frame = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: bounds)
        let context = CIContext()
        let range = try #require(RecordingRange(start: 1, end: 2))
        let start = CGPoint(x: 0.25, y: 0.25)
        let end = CGPoint(x: 0.75, y: 0.75)

        func render(_ kind: RecordingAnnotation.Kind, endpoint: CGPoint? = nil) throws -> CGImage {
            let annotation = RecordingAnnotation(kind: kind, range: range, start: start, end: endpoint ?? end, ink: .white, text: "SuperShot")
            let result = RecordingAnnotationRenderer.render([annotation], at: 1.5, over: frame)
            return try #require(context.createCGImage(result, from: bounds))
        }

        let outline = try render(.outline)
        let arrow = try render(.arrow, endpoint: CGPoint(x: start.x, y: end.y))
        let highlight = try render(.highlight)
        let spotlight = try render(.spotlight)
        let text = try render(.text)
        let inside = CGPoint(x: 58, y: 50)
        let outside = CGPoint(x: 112, y: 82)
        let edge = CGPoint(x: 32, y: 48)
        #expect(try grayscale(outline, at: edge) > 215)
        #expect(try grayscale(arrow, at: edge) > 215)
        #expect(try grayscale(highlight, at: inside) > grayscale(highlight, at: outside))
        #expect(try grayscale(spotlight, at: inside) > grayscale(spotlight, at: outside))
        #expect(try grayscale(text, at: CGPoint(x: 35, y: 26)) < grayscale(text, at: outside))
    }

    @Test func recordingBlurSamplesTheCurrentFrameWithinTheDrawnArea() throws {
        let bounds = CGRect(x: 0, y: 0, width: 128, height: 96)
        let rightHalf = CGRect(x: bounds.midX, y: bounds.minY, width: bounds.width / 2, height: bounds.height)
        let frame = CIImage(color: .white).cropped(to: rightHalf)
            .composited(over: CIImage(color: .black).cropped(to: bounds))
        let blur = RecordingAnnotation(kind: .blur, range: try #require(RecordingRange(start: 1, end: 2)),
                                       start: CGPoint(x: 0.25, y: 0.25), end: CGPoint(x: 0.75, y: 0.75))
        let processed = RecordingAnnotationRenderer.render([blur], at: 1.5, over: frame)
        let image = try #require(CIContext().createCGImage(processed, from: bounds))
        let inside = try grayscale(image, at: CGPoint(x: 67, y: 48))
        #expect(inside > 100 && inside < 240)
        #expect(try grayscale(image, at: CGPoint(x: 67, y: 10)) > 245)
    }

    @Test func timedCameraLayoutsUseSourceTimeAfterCutsAndDecodeOlderEdits() throws {
        let range = try #require(RecordingRange(start: 0, end: 8))
        var edits = RecordingEdits(trim: range)
        let encoded = try JSONEncoder().encode(edits)
        let restored = try JSONDecoder().decode(RecordingEdits.self, from: encoded)
        #expect(restored.annotations == nil)
        #expect(restored.cameraSegments == nil)

        edits.cameraLayout = .hidden
        edits.cuts = [try #require(RecordingRange(start: 2, end: 4))]
        edits.cameraSegments = [
            RecordingCameraSegment(range: try #require(RecordingRange(start: 4, end: 7)), layout: .topLeft),
            RecordingCameraSegment(range: try #require(RecordingRange(start: 5, end: 6)), layout: .cameraOnly),
        ]
        #expect(edits.cameraLayout(at: edits.sourceTime(forEditedTime: 1)) == .hidden)
        #expect(edits.cameraLayout(at: edits.sourceTime(forEditedTime: 2.5)) == .topLeft)
        #expect(edits.cameraLayout(at: edits.sourceTime(forEditedTime: 3.5)) == .cameraOnly)
        #expect(edits.cameraLayout(at: edits.sourceTime(forEditedTime: 5)) == .hidden)
    }

    private func grayscale(_ image: CGImage, at point: CGPoint) throws -> UInt8 {
        let pixel = try #require(image.cropping(to: CGRect(origin: point, size: CGSize(width: 1, height: 1))))
        var bytes = [UInt8](repeating: 0, count: 1)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 1,
                                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return bytes[0]
    }

    private func synthesizeMovie(at url: URL, solidGray: UInt8? = nil) async throws {
        let width = 96
        let height = 64
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        try #require(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        let pool = try #require(adapter.pixelBufferPool)
        for frame in 0..<60 {
            for _ in 0..<100 where !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            try #require(input.isReadyForMoreMediaData)
            var allocated: CVPixelBuffer?
            try #require(CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &allocated) == kCVReturnSuccess)
            let buffer = try #require(allocated)
            CVPixelBufferLockBaseAddress(buffer, [])
            let pixels = CVPixelBufferGetBaseAddress(buffer)
            pixels?.initializeMemory(as: UInt8.self, repeating: solidGray ?? UInt8(frame * 4), count: CVPixelBufferGetDataSize(buffer))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            try #require(adapter.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: 2, timescale: 1))
        await writer.finishWriting()
        try #require(writer.status == .completed)
    }
}

private extension Double {
    func isApproximatelyEqual(to other: Double, tolerance: Double = 0.000_001) -> Bool {
        abs(self - other) <= tolerance
    }
}
