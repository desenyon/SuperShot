import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import Foundation
import os

public enum RecordingCameraLayout: String, Codable, CaseIterable, Sendable {
    case hidden, bottomRight, bottomLeft, topRight, topLeft, circle, split, stacked, cameraOnly

    public var title: String {
        switch self {
        case .hidden: "Hidden"
        case .bottomRight: "Bottom right"
        case .bottomLeft: "Bottom left"
        case .topRight: "Top right"
        case .topLeft: "Top left"
        case .circle: "Circle"
        case .split: "Side by side"
        case .stacked: "Stacked"
        case .cameraOnly: "Camera only"
        }
    }
}

public struct RecordingCameraSegment: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var range: RecordingRange
    public var layout: RecordingCameraLayout

    public init(id: UUID = UUID(), range: RecordingRange, layout: RecordingCameraLayout) {
        self.id = id
        self.range = range
        self.layout = layout
    }
}

public enum RecordingCameraComposition {
    /// Places the already aligned camera track on the same edited timeline as the screen track.
    public static func insertCamera(from screenURL: URL, into composition: AVMutableComposition,
                                    kept: [CMTimeRange], screenStart: CMTime) async throws -> AVCompositionTrack? {
        let cameraURL = RecordingCamera.sidecarURL(for: screenURL)
        guard FileManager.default.fileExists(atPath: cameraURL.path) else { return nil }
        let asset = AVURLAsset(url: cameraURL)
        guard let camera = try await asset.loadTracks(withMediaType: .video).first else { return nil }
        let (available, orientation) = try await camera.load(.timeRange, .preferredTransform)
        guard let target = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw CameraRecordingError.noVideo
        }
        var inserted = false
        do {
            var at = CMTime.zero
            for part in kept {
                let start = available.start + part.start - screenStart
                let piece = CMTimeRange(start: start, duration: part.duration).intersection(available)
                if piece.isValid, piece.duration > .zero {
                    try target.insertTimeRange(piece, of: camera, at: at + piece.start - start)
                    inserted = true
                }
                at = at + part.duration
            }
        } catch {
            composition.removeTrack(target)
            throw error
        }
        guard inserted else {
            composition.removeTrack(target)
            return nil
        }
        target.preferredTransform = orientation
        return target
    }

    public static func make(screen: AVCompositionTrack, camera: AVCompositionTrack, renderSize: CGSize,
                            duration: CMTime, layout: RecordingCameraLayout,
                            renderScreen: @escaping @Sendable (CIImage, CMTime) -> CIImage,
                            renderOutput: @escaping @Sendable (CIImage, CMTime) -> CIImage = { image, _ in image },
                            layoutAtTime: (@Sendable (CMTime) -> RecordingCameraLayout)? = nil) async throws -> AVVideoComposition {
        let screenOrientation = try await screen.load(.preferredTransform)
        let cameraOrientation = try await camera.load(.preferredTransform)
        let instruction = CameraCompositionInstruction(duration: duration, screenID: screen.trackID, cameraID: camera.trackID,
                                                       screenOrientation: screenOrientation, cameraOrientation: cameraOrientation,
                                                       layout: layoutAtTime ?? { _ in layout }, renderScreen: renderScreen, renderOutput: renderOutput)
        let configuration = AVVideoComposition.Configuration(
            animationTool: nil, colorPrimaries: AVVideoColorPrimaries_ITU_R_709_2,
            colorTransferFunction: AVVideoTransferFunction_ITU_R_709_2, colorYCbCrMatrix: AVVideoYCbCrMatrix_ITU_R_709_2,
            customVideoCompositorClass: CameraCompositor.self,
            frameDuration: CMTime(value: 1, timescale: 30), instructions: [instruction], outputBufferDescription: nil,
            renderScale: 1, renderSize: renderSize, sourceSampleDataTrackIDs: [],
            sourceTrackIDForFrameTiming: kCMPersistentTrackID_Invalid, spatialVideoConfigurations: []
        )
        return AVVideoComposition(configuration: configuration)
    }
}

private final class CameraCompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let requiredSourceTrackIDs: [NSValue]?
    let screenID: CMPersistentTrackID
    let cameraID: CMPersistentTrackID
    let screenOrientation: CGAffineTransform
    let cameraOrientation: CGAffineTransform
    let layout: @Sendable (CMTime) -> RecordingCameraLayout
    let renderScreen: @Sendable (CIImage, CMTime) -> CIImage
    let renderOutput: @Sendable (CIImage, CMTime) -> CIImage

    init(duration: CMTime, screenID: CMPersistentTrackID, cameraID: CMPersistentTrackID,
         screenOrientation: CGAffineTransform, cameraOrientation: CGAffineTransform, layout: @escaping @Sendable (CMTime) -> RecordingCameraLayout,
         renderScreen: @escaping @Sendable (CIImage, CMTime) -> CIImage,
         renderOutput: @escaping @Sendable (CIImage, CMTime) -> CIImage) {
        timeRange = CMTimeRange(start: .zero, duration: duration)
        self.screenID = screenID
        self.cameraID = cameraID
        self.screenOrientation = screenOrientation
        self.cameraOrientation = cameraOrientation
        self.layout = layout
        self.renderScreen = renderScreen
        self.renderOutput = renderOutput
        requiredSourceTrackIDs = [NSNumber(value: screenID), NSNumber(value: cameraID)]
    }
}

private final class CameraCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private let queue = DispatchQueue(label: "SuperShot.CameraCompositor")
    private let generation = OSAllocatedUnfairLock(initialState: 0)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    var sourcePixelBufferAttributes: [String: any Sendable]? { requiredPixelBufferAttributesForRenderContext }
    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        let generation = generation.withLock { $0 }
        queue.async {
            guard self.generation.withLock({ $0 }) == generation else {
                request.finishCancelledRequest()
                return
            }
            self.compose(request)
        }
    }

    func cancelAllPendingVideoCompositionRequests() {
        generation.withLock { $0 &+= 1 }
        queue.sync {}
    }

    private func compose(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? CameraCompositionInstruction,
              let source = request.sourceFrame(byTrackID: instruction.screenID),
              let output = request.renderContext.newPixelBuffer() else {
            request.finish(with: CameraRecordingError.noVideo)
            return
        }
        let bounds = CGRect(origin: .zero, size: request.renderContext.size)
        let screen = Self.orient(CIImage(cvPixelBuffer: source), using: instruction.screenOrientation)
        let processed = instruction.renderScreen(screen, request.compositionTime)
        let camera = request.sourceFrame(byTrackID: instruction.cameraID).map {
            Self.orient(CIImage(cvPixelBuffer: $0), using: instruction.cameraOrientation)
        }
        let composite = Self.layout(screen: processed, camera: camera, bounds: bounds, style: instruction.layout(request.compositionTime))
        let frame = instruction.renderOutput(composite, request.compositionTime).cropped(to: bounds)
        context.render(frame, to: output, bounds: bounds, colorSpace: colorSpace)
        request.finish(withComposedVideoFrame: output)
    }

    private static func orient(_ image: CIImage, using orientation: CGAffineTransform) -> CIImage {
        guard !orientation.isIdentity else { return image }
        let oriented = image.extent.applying(orientation)
        let flipSource = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: image.extent.height)
        let flipTarget = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: -oriented.minX, ty: oriented.maxY)
        return image.transformed(by: flipSource.concatenating(orientation).concatenating(flipTarget))
    }

    private static func layout(screen: CIImage, camera: CIImage?, bounds: CGRect, style: RecordingCameraLayout) -> CIImage {
        let background = CIImage(color: .black).cropped(to: bounds)
        guard let camera, style != .hidden else { return place(screen, in: bounds).composited(over: background) }
        switch style {
        case .bottomRight, .bottomLeft, .topLeft, .topRight, .circle:
            let inset = min(bounds.width, bounds.height) * 0.04
            let width = style == .circle ? min(bounds.width, bounds.height) * 0.28 : bounds.width * 0.24
            let height = style == .circle ? width : min(bounds.height * 0.34, width * camera.extent.height / camera.extent.width)
            let x = style == .bottomLeft || style == .topLeft ? bounds.minX + inset : bounds.maxX - width - inset
            let y = style == .topLeft || style == .topRight ? bounds.maxY - height - inset : bounds.minY + inset
            let frame = CGRect(x: x, y: y, width: width, height: height)
            let view = place(camera, in: frame, fill: true).cropped(to: frame)
            let mask = CIFilter.roundedRectangleGenerator()
            mask.extent = frame
            mask.radius = Float(min(width, height) * (style == .circle ? 0.5 : 0.08))
            mask.color = .white
            let cornered = mask.outputImage.map {
                view.applyingFilter("CIBlendWithAlphaMask", parameters: [
                    kCIInputMaskImageKey: $0, kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: frame)
                ])
            } ?? view
            return cornered.composited(over: place(screen, in: bounds).composited(over: background))
        case .split:
            let gap = bounds.width * 0.02
            let split = bounds.width * 0.58
            let left = CGRect(x: 0, y: 0, width: split - gap / 2, height: bounds.height)
            let right = CGRect(x: split + gap / 2, y: 0, width: bounds.width - split - gap / 2, height: bounds.height)
            return place(camera, in: right, fill: true).cropped(to: right)
                .composited(over: place(screen, in: left).composited(over: background))
        case .stacked:
            let gap = bounds.height * 0.02
            let split = bounds.height * 0.38
            let lower = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: split - gap / 2)
            let upper = CGRect(x: bounds.minX, y: bounds.minY + split + gap / 2, width: bounds.width, height: bounds.height - split - gap / 2)
            return place(camera, in: lower, fill: true).cropped(to: lower)
                .composited(over: place(screen, in: upper).composited(over: background))
        case .cameraOnly:
            return place(camera, in: bounds, fill: true).cropped(to: bounds).composited(over: background)
        case .hidden:
            return place(screen, in: bounds).composited(over: background)
        }
    }

    private static func place(_ image: CIImage, in frame: CGRect, fill: Bool = false) -> CIImage {
        let source = image.extent
        let horizontal = frame.width / source.width
        let vertical = frame.height / source.height
        let scale = fill ? max(horizontal, vertical) : min(horizontal, vertical)
        return image.transformed(by: CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                                       tx: frame.midX - source.midX * scale,
                                                       ty: frame.midY - source.midY * scale))
    }
}
