import Foundation

/// Pure geometry shared by the pin's pointer and keyboard resizing paths.
public enum PinGeometry {
    public struct Edges: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let left = Edges(rawValue: 1)
        public static let right = Edges(rawValue: 2)
        public static let bottom = Edges(rawValue: 4)
        public static let top = Edges(rawValue: 8)
    }
    public static func edges(at point: CGPoint, size: CGSize, inset: CGFloat = DS.pinResizeInset) -> Edges {
        var edges: Edges = []
        if point.x < inset { edges.insert(.left) }
        else if point.x > size.width - inset { edges.insert(.right) }
        if point.y < inset { edges.insert(.bottom) }
        else if point.y > size.height - inset { edges.insert(.top) }
        return edges
    }
    public static func fittedSize(image: CGSize, longestEdge: CGFloat, available: CGSize) -> CGSize {
        guard image.width > 0, image.height > 0 else { return .zero }
        let scale = min(1, longestEdge / max(image.width, image.height), available.width / image.width, available.height / image.height)
        return CGSize(width: image.width * scale, height: image.height * scale)
    }
    public static func resize(_ frame: CGRect, edges: Edges, delta: CGPoint, available: CGSize) -> CGRect {
        guard frame.width > 0, frame.height > 0, !edges.isEmpty else { return frame }
        let dx = edges.contains(.left) ? -delta.x : delta.x
        let dy = edges.contains(.bottom) ? -delta.y : delta.y
        let horizontal = edges.contains(.left) || edges.contains(.right)
        let vertical = edges.contains(.top) || edges.contains(.bottom)
        let xScale = (frame.width + dx) / frame.width
        let yScale = (frame.height + dy) / frame.height
        let proposed = horizontal && vertical ? (abs(dx / frame.width) > abs(dy / frame.height) ? xScale : yScale) : (horizontal ? xScale : yScale)
        let maximum = min(available.width / frame.width, available.height / frame.height)
        let minimum = min(maximum, DS.pinMinimumLongEdge / max(frame.width, frame.height))
        let scale = max(minimum, min(maximum, proposed))
        let size = CGSize(width: frame.width * scale, height: frame.height * scale)
        let x = edges.contains(.left) ? frame.maxX - size.width : (horizontal ? frame.minX : frame.midX - size.width / 2)
        let y = edges.contains(.bottom) ? frame.maxY - size.height : (vertical ? frame.minY : frame.midY - size.height / 2)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}
