import Foundation
import CoreGraphics
import ScreenCaptureKit

public struct CapturedImage: Sendable {
    public let id: UUID
    public let image: CGImage
    public let scale: CGFloat
    public let date: Date
    public let source: String
    public let applicationName: String?
    public let windowTitle: String?
    public init(image: CGImage, scale: CGFloat, source: String, id: UUID = UUID(), date: Date = .now,
                applicationName: String? = nil, windowTitle: String? = nil) {
        self.id = id; self.image = image; self.scale = scale; self.date = date; self.source = source
        self.applicationName = applicationName; self.windowTitle = windowTitle
    }
    public func replacingImage(_ image: CGImage) -> CapturedImage {
        CapturedImage(image: image, scale: scale, source: source, id: id, date: date,
                      applicationName: applicationName, windowTitle: windowTitle)
    }
}
public struct CaptureWindow: Sendable, Identifiable {
    public let id: CGWindowID
    public let title: String
    public let frame: CGRect
    public init(id: CGWindowID, title: String, frame: CGRect) { self.id = id; self.title = title; self.frame = frame }
}
public enum CaptureFailure: LocalizedError {
    case missingDisplay, missingWindow, emptyImage
    public var errorDescription: String? {
        switch self {
        case .missingDisplay: "The display is no longer connected. Try capturing again."
        case .missingWindow: "That window is no longer available. Choose another window."
        case .emptyImage: "macOS returned an empty image. Check Screen Recording access and try again."
        }
    }
}
public actor CaptureService {
    private var displayContent: SCShareableContent?
    public init() {}
    public func prepare() async throws {
        displayContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }
    public func invalidate() { displayContent = nil }

    public func screen(id: CGDirectDisplayID, cursor: Bool = false, hideDesktopIcons: Bool = false) async throws -> CapturedImage {
        if hideDesktopIcons || displayContent?.displays.first(where: { $0.displayID == id })?.frame.size != CGDisplayBounds(id).size {
            try await prepare()
        }
        guard let content = displayContent else { throw CaptureFailure.missingDisplay }
        guard let display = content.displays.first(where: { $0.displayID == id }) else { throw CaptureFailure.missingDisplay }
        let excluded = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier || (hideDesktopIcons && $0.bundleIdentifier == "com.apple.finder") }
        let finderWindows = hideDesktopIcons ? content.windows.filter { $0.owningApplication?.bundleIdentifier == "com.apple.finder" && $0.windowLayer == 0 } : []
        let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: finderWindows)
        return try await capture(filter: filter, displayID: id, cursor: cursor, source: "Display \(id)")
    }
    public func windows() async throws -> [CaptureWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let ordered = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? [])
            .compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
        let ranks = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($0.element, $0.offset) })
        return content.windows.sorted { (ranks[$0.windowID] ?? Int.max) < (ranks[$1.windowID] ?? Int.max) }.filter {
            $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier && $0.windowLayer == 0 && $0.frame.width > 40 && $0.frame.height > 40
        }.map { CaptureWindow(id: $0.windowID, title: [$0.owningApplication?.applicationName, $0.title].compactMap { $0 }.joined(separator: " — "), frame: $0.frame) }
    }
    public func window(id: CGWindowID, cursor: Bool = false, keepShadow: Bool = false) async throws -> CapturedImage {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == id }) else { throw CaptureFailure.missingWindow }
        let app = window.owningApplication?.applicationName
        let title = window.title
        let name = [app, title].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        let displayID = content.displays.first(where: { $0.frame.contains(center) })?.displayID ?? CGMainDisplayID()
        return try await capture(filter: SCContentFilter(desktopIndependentWindow: window), displayID: displayID,
                                 cursor: cursor, source: name.isEmpty ? "Window" : name, keepShadow: keepShadow,
                                 app: app, title: title)
    }
    private func capture(filter: SCContentFilter, displayID: CGDirectDisplayID, cursor: Bool, source: String,
                         keepShadow: Bool = false, app: String? = nil, title: String? = nil) async throws -> CapturedImage {
        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        // Capture every native pixel: round instead of truncating, and never let the system rescale.
        config.width = Int((filter.contentRect.width * scale).rounded())
        config.height = Int((filter.contentRect.height * scale).rounded())
        config.scalesToFit = false
        // Keep wide-gamut color on displays that have it instead of squeezing the capture into sRGB.
        let wideGamut = CGDisplayCopyColorSpace(displayID).isWideGamutRGB
        config.colorSpaceName = wideGamut ? CGColorSpace.displayP3 : CGColorSpace.sRGB
        config.showsCursor = cursor
        config.ignoreShadowsSingleWindow = !keepShadow
        config.captureResolution = .best
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return CapturedImage(image: image, scale: scale, source: source, applicationName: app, windowTitle: title)
    }
}

public enum SelectionGeometry {
    public static func rectangle(from start: CGPoint, to end: CGPoint, bounds: CGRect) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y)).intersection(bounds)
    }
    /// View and CGImage crops both use top-left coordinates here.
    public static func pixels(selection: CGRect, viewSize: CGSize, imageSize: CGSize) -> CGRect {
        guard viewSize.width > 0, viewSize.height > 0 else { return .zero }
        return CGRect(x: selection.minX * imageSize.width / viewSize.width,
                      y: selection.minY * imageSize.height / viewSize.height,
                      width: selection.width * imageSize.width / viewSize.width,
                      height: selection.height * imageSize.height / viewSize.height)
            .integral.intersection(CGRect(origin: .zero, size: imageSize))
    }
}
