import AVFoundation
import CoreImage
import CoreMedia
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct RecordingArchive: Sendable {
    public let folder: URL

    public init(folder: URL? = nil) {
        self.folder = folder ?? URL.applicationSupportDirectory.appending(path: "SuperShot/Recordings", directoryHint: .isDirectory)
    }

    public func reserve() throws -> URL {
        let staging = folder.appending(path: ".staging", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return staging.appending(path: UUID().uuidString).appendingPathExtension("mp4")
    }

    public func commit(_ source: URL, at date: Date = .now) throws -> URL {
        let stamp = date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: "-")
        let suffix = source.deletingPathExtension().lastPathComponent.prefix(8)
        let target = folder.appending(path: "Recording \(stamp) \(suffix)").appendingPathExtension("mp4")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: source.path)
        try FileManager.default.moveItem(at: source, to: target)
        return target
    }

    public func recordings() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        let keys: Set<URLResourceKey> = [.creationDateKey, .isRegularFileKey]
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys), options: .skipsHiddenFiles)
        let entries: [(url: URL, date: Date)] = files.compactMap { url in
            guard url.pathExtension.lowercased() == "mp4", let metadata = try? url.resourceValues(forKeys: keys),
                  metadata.isRegularFile == true else { return nil }
            return (url, metadata.creationDate ?? .distantPast)
        }
        return entries.sorted { $0.date == $1.date ? $0.url.lastPathComponent > $1.url.lastPathComponent : $0.date > $1.date }.map(\.url)
    }
}

public struct RecordingRange: Codable, Equatable, Sendable {
    public let start: TimeInterval
    public let end: TimeInterval
    public var duration: TimeInterval { end - start }

    public init?(start: TimeInterval, end: TimeInterval) {
        guard start.isFinite, end.isFinite, start >= 0, end > start else { return nil }
        self.start = start
        self.end = end
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let start = try values.decode(TimeInterval.self, forKey: .start)
        let end = try values.decode(TimeInterval.self, forKey: .end)
        guard let valid = Self(start: start, end: end) else { throw RecordingFailure.invalidRange }
        self = valid
    }

    public func intersection(_ other: Self) -> Self? {
        Self(start: max(start, other.start), end: min(end, other.end))
    }

    public func excluding(_ cuts: [Self]) -> [Self] {
        var start = start
        var kept: [Self] = []
        for cut in cuts.sorted(by: { $0.start < $1.start }) {
            guard let clipped = intersection(cut) else { continue }
            if let part = Self(start: start, end: clipped.start) { kept.append(part) }
            start = max(start, clipped.end)
        }
        if let tail = Self(start: start, end: end) { kept.append(tail) }
        return kept
    }

    fileprivate var timeRange: CMTimeRange {
        CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 6000), end: CMTime(seconds: end, preferredTimescale: 6000))
    }
}

public enum RecordingPerspective: String, Codable, CaseIterable, Sendable {
    case flat = "Flat"
    case left = "Tilt left"
    case right = "Tilt right"
}

public enum RecordingCaptionStyle: String, Codable, CaseIterable, Sendable {
    case lightText = "Light text"
    case darkText = "Dark text"
}

public struct RecordingZoom: Codable, Equatable, Sendable {
    public let range: RecordingRange
    public let center: CGPoint

    public init(range: RecordingRange, center: CGPoint = CGPoint(x: 0.5, y: 0.5)) {
        self.range = range
        self.center = center
    }

    public static func atClick(_ point: CGPoint, in bounds: CGRect, time: TimeInterval, after previous: Self?) -> Self? {
        guard bounds.width > 0, bounds.height > 0, bounds.contains(point), time.isFinite, time >= 0,
              time >= (previous?.range.end ?? 0), let range = RecordingRange(start: time, end: time + 1.7) else { return nil }
        return RecordingZoom(range: range, center: CGPoint(x: (point.x - bounds.minX) / bounds.width,
                                                            y: (point.y - bounds.minY) / bounds.height))
    }
}

public struct RecordingEdits: Codable, Equatable, Sendable {
    public var trim: RecordingRange
    public var cuts: [RecordingRange] = []
    public var zooms: [RecordingZoom] = []
    public var perspective: RecordingPerspective = .flat
    public var audioLevels: [Float] = []
    public var captionStyle: RecordingCaptionStyle?
    public var cameraLayout: RecordingCameraLayout?
    public var cameraSegments: [RecordingCameraSegment]?
    public var annotations: [RecordingAnnotation]?

    public func cameraLayout(at sourceTime: TimeInterval) -> RecordingCameraLayout {
        cameraSegments?.last(where: { $0.range.start <= sourceTime && sourceTime < $0.range.end })?.layout
            ?? cameraLayout ?? .bottomRight
    }

    public init(trim: RecordingRange) { self.trim = trim }

    public var kept: [RecordingRange] { trim.excluding(cuts) }
    public var duration: TimeInterval { kept.reduce(0) { $0 + $1.duration } }

    public func sourceTime(forEditedTime time: TimeInterval) -> TimeInterval {
        var remaining = max(0, time)
        for part in kept {
            if remaining < part.duration { return part.start + remaining }
            remaining -= part.duration
        }
        return kept.last?.end ?? trim.start
    }

    public func editedTime(forSourceTime time: TimeInterval) -> TimeInterval {
        var elapsed: TimeInterval = 0
        for part in kept {
            if time <= part.end { return elapsed + max(0, time - part.start) }
            elapsed += part.duration
        }
        return elapsed
    }
}

public struct RecordingMediaInfo: Sendable {
    public let range: RecordingRange
    public let pixelSize: CGSize
    public let frameDuration: TimeInterval
    public let audioTrackCount: Int
    public let hasCamera: Bool
}

public struct RecordingPlayback {
    public let asset: AVAsset
    public let videoComposition: AVVideoComposition?
    public let audioMix: AVAudioMix?
}

public enum RecordingFormat: String, CaseIterable, Sendable {
    case mp4 = "MP4"
    case gif = "GIF"
}

public enum RecordingMedia {
    public static let maxGIFDuration: TimeInterval = 30

    public static func editsURL(for url: URL) -> URL { url.deletingPathExtension().appendingPathExtension("supershot-video.json") }
    public static func transcriptURL(for url: URL) -> URL { url.deletingPathExtension().appendingPathExtension("supershot-transcript.json") }

    public static func inspect(_ url: URL) async throws -> RecordingMediaInfo {
        let asset = AVURLAsset(url: url)
        guard let video = try await asset.loadTracks(withMediaType: .video).first else { throw RecordingFailure.empty }
        let videoRange = try await video.load(.timeRange)
        guard let range = RecordingRange(start: max(0, videoRange.start.seconds), end: videoRange.end.seconds) else { throw RecordingFailure.empty }
        let (naturalSize, transform, frameRate) = try await video.load(.naturalSize, .preferredTransform, .nominalFrameRate)
        let size = naturalSize.applying(transform)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let cameraFile = RecordingCamera.sidecarURL(for: url)
        var hasCamera = false
        if FileManager.default.fileExists(atPath: cameraFile.path) {
            let tracks = try? await AVURLAsset(url: cameraFile).loadTracks(withMediaType: .video)
            hasCamera = tracks?.isEmpty == false
        }
        return RecordingMediaInfo(range: range, pixelSize: CGSize(width: abs(size.width), height: abs(size.height)),
                                  frameDuration: frameRate.isFinite && frameRate > 0 ? 1 / Double(frameRate) : 1.0 / 30,
                                  audioTrackCount: audio.count, hasCamera: hasCamera)
    }

    public static func playback(_ url: URL, edits: RecordingEdits, transcript: [RecordingCue] = []) async throws -> RecordingPlayback {
        let input = AVURLAsset(url: url)
        guard let video = try await input.loadTracks(withMediaType: .video).first else { throw RecordingFailure.empty }
        let videoRange = try await video.load(.timeRange)
        let kept = edits.kept.map { $0.timeRange.intersection(videoRange) }.filter { $0.duration > .zero }
        guard !kept.isEmpty else { throw RecordingFailure.invalidRange }

        let result = AVMutableComposition()
        guard let target = result.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw RecordingFailure.exportUnavailable
        }
        target.preferredTransform = try await video.load(.preferredTransform)
        var time = CMTime.zero
        for part in kept {
            try target.insertTimeRange(part, of: video, at: time)
            time = time + part.duration
        }

        let audioTracks = try await input.loadTracks(withMediaType: .audio)
        var audioMixInputs: [AVAudioMixInputParameters] = []
        for (index, audio) in audioTracks.enumerated() {
            let available = try await audio.load(.timeRange)
            guard let track = result.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw RecordingFailure.exportUnavailable
            }
            var time = CMTime.zero
            for part in kept {
                let piece = part.intersection(available)
                if piece.duration > .zero {
                    try track.insertTimeRange(piece, of: audio, at: time + piece.start - part.start)
                }
                time = time + part.duration
            }
            let level = index < edits.audioLevels.count ? edits.audioLevels[index] : 1
            let params = AVMutableAudioMixInputParameters(track: track)
            params.setVolume(level.isFinite ? min(1, max(0, level)) : 1, at: .zero)
            audioMixInputs.append(params)
        }
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = audioMixInputs

        let visual = try await visualEffects(source: url, video: video, target: target, composition: result, trimmed: kept,
                                             screenStart: videoRange.start, end: time, edits: edits, transcript: transcript)
        return RecordingPlayback(asset: result, videoComposition: visual, audioMix: audioMixInputs.isEmpty ? nil : audioMix)
    }

    private static func visualEffects(source: URL, video: AVAssetTrack, target: AVCompositionTrack, composition: AVMutableComposition,
                                      trimmed: [CMTimeRange], screenStart: CMTime, end: CMTime,
                                      edits: RecordingEdits, transcript: [RecordingCue]) async throws -> AVVideoComposition? {
        let captions = edits.captionStyle == nil ? [] : RecordingTranscript.captions(transcript, in: edits)
        let renderScreen: @Sendable (CIImage, CMTime) -> CIImage = { image, time in
            render(image, at: edits.sourceTime(forEditedTime: time.seconds), edits: edits)
        }
        let renderOutput: @Sendable (CIImage, CMTime) -> CIImage = { image, time in
            let editedTime = time.seconds
            let frame = RecordingAnnotationRenderer.render(edits.annotations ?? [], at: edits.sourceTime(forEditedTime: editedTime), over: image)
            guard let style = edits.captionStyle,
                  let caption = captions.last(where: { $0.range.start <= editedTime && editedTime < $0.range.end }),
                  let overlay = captionImage(caption.text, style: style, bounds: frame.extent) else { return frame }
            return overlay.composited(over: frame).cropped(to: frame.extent)
        }
        let layout = edits.cameraLayout ?? .bottomRight
        if layout != .hidden || edits.cameraSegments?.contains(where: { $0.layout != .hidden }) == true,
           let camera = try? await RecordingCameraComposition.insertCamera(from: source, into: composition, kept: trimmed, screenStart: screenStart) {
            let (size, orientation) = try await video.load(.naturalSize, .preferredTransform)
            let displaySize = size.applying(orientation)
            let sizeInPixels = CGSize(width: abs(displaySize.width), height: abs(displaySize.height))
            return try await RecordingCameraComposition.make(screen: target, camera: camera, renderSize: sizeInPixels, duration: end,
                                                             layout: layout, renderScreen: renderScreen, renderOutput: renderOutput,
                                                             layoutAtTime: { edits.cameraLayout(at: edits.sourceTime(forEditedTime: $0.seconds)) })
        }
        guard !edits.zooms.isEmpty || edits.perspective != .flat || !captions.isEmpty || edits.annotations?.isEmpty == false else { return nil }
        return try await AVVideoComposition(applyingFiltersTo: composition) { frame in
            let edited = renderScreen(frame.sourceImage, frame.compositionTime)
            return AVCIImageFilteringResult(resultImage: renderOutput(edited, frame.compositionTime))
        }
    }

    public static func export(_ source: URL, to destination: URL, format: RecordingFormat, edits: RecordingEdits,
                              transcript: [RecordingCue] = []) async throws {
        try validateDestination(destination, source: source)
        let playback = try await playback(source, edits: edits, transcript: transcript)
        let temp = destination.deletingLastPathComponent().appending(path: ".supershot-\(UUID().uuidString)")
            .appendingPathExtension(format.rawValue.lowercased())
        defer { try? FileManager.default.removeItem(at: temp) }
        switch format {
        case .mp4:
            guard let session = AVAssetExportSession(asset: playback.asset, presetName: AVAssetExportPresetHighestQuality) else {
                throw RecordingFailure.exportUnavailable
            }
            session.videoComposition = playback.videoComposition
            session.audioMix = playback.audioMix
            session.shouldOptimizeForNetworkUse = true
            try await session.export(to: temp, as: .mp4)
        case .gif:
            try await exportGIF(playback, to: temp)
        }
        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temp)
        } else {
            try FileManager.default.moveItem(at: temp, to: destination)
        }
    }

    public static func validateDestination(_ destination: URL, source: URL) throws {
        let reserved = [source, editsURL(for: source), RecordingCamera.sidecarURL(for: source), transcriptURL(for: source)]
        let output = destination.resolvingSymlinksInPath().standardizedFileURL
        guard !reserved.contains(where: { $0.resolvingSymlinksInPath().standardizedFileURL == output }) else {
            throw RecordingFailure.invalidDestination
        }
    }

    private static func exportGIF(_ playback: RecordingPlayback, to destination: URL) async throws {
        let duration = try await playback.asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw RecordingFailure.invalidRange }
        guard duration <= maxGIFDuration else { throw RecordingFailure.gifTooLong }
        let frames = max(1, Int(ceil(duration * 12)))
        let frameDuration = duration / Double(frames)
        guard let writer = CGImageDestinationCreateWithURL(destination as CFURL, UTType.gif.identifier as CFString, frames, nil) else {
            throw RecordingFailure.exportUnavailable
        }
        CGImageDestinationSetProperties(writer, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let properties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: frameDuration,
                                                         kCGImagePropertyGIFUnclampedDelayTime: frameDuration]] as CFDictionary
        let generator = AVAssetImageGenerator(asset: playback.asset)
        generator.appliesPreferredTrackTransform = true
        generator.videoComposition = playback.videoComposition
        generator.maximumSize = CGSize(width: 960, height: 960)
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 24)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 24)
        for frame in 0..<frames {
            try Task.checkCancellation()
            let time = CMTime(seconds: Double(frame) * frameDuration, preferredTimescale: 6000)
            let image = try await generator.image(at: time).image
            CGImageDestinationAddImage(writer, image, properties)
        }
        guard CGImageDestinationFinalize(writer) else { throw RecordingFailure.exportUnavailable }
    }

    private static func render(_ source: CIImage, at time: TimeInterval, edits: RecordingEdits) -> CIImage {
        let bounds = source.extent
        var image = source
        if let zoom = edits.zooms.last(where: { $0.range.start <= time && time < $0.range.end }) {
            let rampLength = min(0.4, zoom.range.duration / 2)
            let fraction = min(1, (time - zoom.range.start) / rampLength, (zoom.range.end - time) / rampLength)
            let scale = 1 + 0.4 * fraction * fraction * (3 - 2 * fraction)
            let focus = CGPoint(x: bounds.minX + bounds.width * zoom.center.x, y: bounds.minY + bounds.height * zoom.center.y)
            let x = min(bounds.minX * (1 - scale), max(bounds.maxX * (1 - scale), bounds.midX - focus.x * scale))
            let y = min(bounds.minY * (1 - scale), max(bounds.maxY * (1 - scale), bounds.midY - focus.y * scale))
            let transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: x, ty: y)
            image = image.transformed(by: transform).cropped(to: bounds)
        }
        guard edits.perspective != .flat else { return image }
        let outer = bounds.insetBy(dx: bounds.width * 0.08, dy: bounds.height * 0.08)
        let tilt = bounds.height * 0.10
        let left = edits.perspective == .left ? tilt : 0
        let right = edits.perspective == .right ? tilt : 0
        image = image.applyingFilter("CIPerspectiveTransform", parameters: [
            "inputTopLeft": CIVector(x: outer.minX, y: outer.maxY - left),
            "inputBottomLeft": CIVector(x: outer.minX, y: outer.minY + left),
            "inputTopRight": CIVector(x: outer.maxX, y: outer.maxY - right),
            "inputBottomRight": CIVector(x: outer.maxX, y: outer.minY + right),
        ])
        return image.composited(over: CIImage(color: .black).cropped(to: bounds)).cropped(to: bounds)
    }

    private static func captionImage(_ text: String, style: RecordingCaptionStyle, bounds: CGRect) -> CIImage? {
        let padding = bounds.height * 0.014
        let maxWidth = bounds.width * 0.82
        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, bounds.height * 0.044, nil)
            ?? CTFontCreateWithName("HelveticaNeue-Medium" as CFString, bounds.height * 0.044, nil)
        let foreground = CGColor(gray: style == .lightText ? 1 : 0, alpha: 1)
        let background = CGColor(gray: style == .lightText ? 0 : 1, alpha: 0.86)
        let label = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): foreground,
        ])
        let typesetter = CTTypesetterCreateWithAttributedString(label)
        var lines: [CTLine] = []
        var offset = 0
        while offset < label.length {
            let length = CTTypesetterSuggestLineBreak(typesetter, offset, maxWidth)
            guard length > 0 else { break }
            lines.append(CTTypesetterCreateLine(typesetter, CFRange(location: offset, length: length)))
            offset += length
        }
        guard !lines.isEmpty else { return nil }
        let lineHeight = ceil(CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font))
        let widest = lines.map { CTLineGetTypographicBounds($0, nil, nil, nil) }.max() ?? 0
        let width = Int(ceil(widest + padding * 2))
        let height = Int(ceil(lineHeight * Double(lines.count) + padding * 2))
        guard let bitmap = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let tile = CGRect(x: 0, y: 0, width: width, height: height)
        bitmap.setFillColor(background)
        bitmap.addPath(CGPath(roundedRect: tile, cornerWidth: padding, cornerHeight: padding, transform: nil))
        bitmap.fillPath()
        for (index, line) in lines.enumerated() {
            let lineWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
            bitmap.textPosition = CGPoint(x: (Double(width) - lineWidth) / 2, y: Double(height) - padding - CTFontGetAscent(font) - Double(index) * lineHeight)
            CTLineDraw(line, bitmap)
        }
        guard let rendered = bitmap.makeImage() else { return nil }
        return CIImage(cgImage: rendered).transformed(by: CGAffineTransform(translationX: bounds.midX - Double(width) / 2,
                                                                         y: bounds.minY + bounds.height * 0.055))
    }
}
