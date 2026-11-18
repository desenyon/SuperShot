import Foundation
import Document
import DesignSystem

public struct ToolStyle: Sendable {
    public var color = RGBA(red: 1, green: 0.28, blue: 0.29)
    public var stroke: Double = 5
    public var opacity: Double = 1
    public var filled = false
    public var fontSize: Double = 28
    public var arrowHead = "filled"
    public var arrowBend: Double = 0
    public var textBackground = false
    public var textOutline = false
    public init() {}
}

public protocol Tool: Sendable {
    var kind: LayerKind { get }
    var title: String { get }
    var symbol: String { get }
    var shortcut: String { get }
    func makeLayer(start: CGPoint, end: CGPoint, points: [CGPoint], style: ToolStyle) -> Layer
}
public extension Tool {
    func makeLayer(start: CGPoint, end: CGPoint, points: [CGPoint], style: ToolStyle) -> Layer {
        var layer=Layer(kind: kind, rect: CGRect(x: min(start.x,end.x), y: min(start.y,end.y), width: max(1,abs(start.x-end.x)), height: max(1,abs(start.y-end.y))), points: points.isEmpty ? [start,end] : points, color: style.color, stroke: style.stroke, opacity: style.opacity, filled: style.filled, fontSize: style.fontSize)
        if kind == .arrow {layer.arrowHead=style.arrowHead;layer.arrowBend=style.arrowBend}
        return layer
    }
}
public struct RectangleTool: Tool { public let kind = LayerKind.rectangle; public let title="Rectangle"; public let symbol="rectangle"; public let shortcut="r"; public init() {} }
public struct OvalTool: Tool { public let kind = LayerKind.oval; public let title="Oval"; public let symbol="circle"; public let shortcut="o"; public init() {} }
public struct LineTool: Tool { public let kind = LayerKind.line; public let title="Line"; public let symbol="line.diagonal"; public let shortcut="l"; public init() {} }
public struct ArrowTool: Tool { public let kind = LayerKind.arrow; public let title="Arrow"; public let symbol="arrow.up.right"; public let shortcut="a"; public init() {} }
public struct DrawingTool: Tool { public let kind = LayerKind.drawing; public let title="Draw"; public let symbol="pencil.tip"; public let shortcut="d"; public init() {} }
public struct HighlighterTool: Tool { public let kind = LayerKind.highlighter; public let title="Highlighter"; public let symbol="highlighter"; public let shortcut="h"; public init() {} }
public struct TextTool: Tool { public let kind = LayerKind.text; public let title="Text"; public let symbol="textformat"; public let shortcut="t"; public init() {} }
public struct CounterTool: Tool { public let kind = LayerKind.counter; public let title="Counter"; public let symbol="1.circle"; public let shortcut="n"; public init() {} }
public struct BlurTool: Tool { public let kind = LayerKind.blur; public let title="Blur"; public let symbol="drop.halffull"; public let shortcut="b"; public init() {} }
public struct PixelateTool: Tool { public let kind = LayerKind.pixelate; public let title="Pixelate"; public let symbol="square.grid.3x3"; public let shortcut="x"; public init() {} }
public struct SpotlightTool: Tool { public let kind = LayerKind.spotlight; public let title="Spotlight"; public let symbol="flashlight.on.fill"; public let shortcut="s"; public init() {} }
public struct MagnifierTool: Tool { public let kind = LayerKind.magnifier; public let title="Magnifier"; public let symbol="plus.magnifyingglass"; public let shortcut="m"; public init() {} }
public struct EraseTool: Tool { public let kind = LayerKind.erase; public let title="Erase with color"; public let symbol="eraser"; public let shortcut="e"; public init() {} }
public struct RulerTool: Tool { public let kind = LayerKind.ruler; public let title="Ruler"; public let symbol="ruler"; public let shortcut="u"; public init() {} }
public enum ToolRegistry {
    public static let tools: [any Tool] = [ArrowTool(), RectangleTool(), OvalTool(), LineTool(), TextTool(), DrawingTool(), HighlighterTool(), CounterTool(), BlurTool(), PixelateTool(), SpotlightTool(), MagnifierTool(), EraseTool(), RulerTool()]
    public static func tool(_ id: String) -> (any Tool)? { tools.first { $0.kind.rawValue == id } }
}

/// The visible tool palette. Shortcut resolution stays in the canvas and uses the full registry.
public struct EditorChrome: Equatable, Sendable {
    private static let groups = [
        ["select", "crop"], ["arrow", "rectangle", "oval", "line"],
        ["text", "counter", "drawing", "highlighter"], ["blur", "pixelate", "erase", "spotlight", "magnifier"],
        ["ruler", "picker"], ["image"]
    ]
    public static let defaultTools = groups.flatMap { $0 }
    public let tools: [String]

    public init(tools: [String] = Self.defaultTools) {
        var seen = Set<String>()
        self.tools = tools.filter { Self.defaultTools.contains($0) && seen.insert($0).inserted }
    }

    func beginsGroup(at index: Int) -> Bool {
        index > 0 && !Self.groups.contains { $0.contains(tools[index - 1]) && $0.contains(tools[index]) }
    }
}
