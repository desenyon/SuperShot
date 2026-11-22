import CoreGraphics

public enum RecordingSourceGeometry {
    /// ScreenCaptureKit interprets the source rectangle in display-local points from the top left.
    public static func crop(_ rect: CGRect, on display: CGRect) -> CGRect? {
        guard [rect.minX, rect.minY, rect.width, rect.height, display.width, display.height].allSatisfy(\.isFinite),
              rect.size.width >= 2, rect.size.height >= 2, display.width >= 2, display.height >= 2 else { return nil }
        let clipped = rect.intersection(CGRect(origin: .zero, size: display.size))
        guard !clipped.isNull, clipped.width >= 2, clipped.height >= 2 else { return nil }
        return clipped
    }

    /// Converts the same source area for comparing with global AppKit mouse coordinates.
    public static func appKitBounds(of crop: CGRect, on display: CGRect) -> CGRect {
        CGRect(x: display.minX + crop.minX, y: display.maxY - crop.maxY, width: crop.width, height: crop.height)
    }

    static func previewPixels(for size: CGSize) -> CGSize? {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, 320 / size.width, 240 / size.height)
        return CGSize(width: max(1, (size.width * scale).rounded()), height: max(1, (size.height * scale).rounded()))
    }
}
