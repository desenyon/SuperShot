import AppKit
import DesignSystem

/// What to do with a selected area, chosen from the bar under the selection.
public enum OverlayAction: String, CaseIterable, Sendable {
    /// Follow the user's "after an area capture" setting.
    case capture, copy, save, edit, pin, text
    var title: String {
        switch self { case .capture: "Capture"; case .copy: "Copy"; case .save: "Save"; case .edit: "Edit"; case .pin: "Pin"; case .text: "Text" }
    }
    var symbol: String {
        switch self {
        case .capture: "camera.viewfinder"; case .copy: "doc.on.doc"; case .save: "square.and.arrow.down"
        case .edit: "pencil.tip.crop.circle"; case .pin: "pin"; case .text: "text.viewfinder"
        }
    }
}

@MainActor public final class SelectionOverlay {
    private var window: OverlayWindow?
    public init() {}
    public func show(screen: NSScreen, capture: CapturedImage, windows: [CaptureWindow]? = nil, snappingWindows: [CaptureWindow] = [], showsActions: Bool = false, captureOnRelease: Bool = false, completion: @escaping (CGRect?, CGWindowID?, OverlayAction) -> Void) {
        dismiss()
        let window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .screenSaver; window.backgroundColor = .clear; window.isOpaque = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false; window.acceptsMouseMovedEvents = true
        let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size), capture: capture, windows: windows, snappingWindows: snappingWindows, screenOrigin: CGDisplayBounds(screen.displayID).origin) { [weak self] rect, id, action in
            self?.dismiss(); completion(rect, id, action)
        }
        view.showsActions = showsActions
        view.captureOnRelease = captureOnRelease
        window.contentView = view; self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil); window.makeFirstResponder(view)
    }
    public func dismiss() { window?.orderOut(nil); window = nil }

    /// A detached overlay view in a fixed state, for offscreen design review. Never shown on screen.
    public static func previewView(size: CGSize, capture: CapturedImage, windows: [CaptureWindow]? = nil, selection: CGRect, pointer: CGPoint, captureOnRelease: Bool = false) -> NSView {
        let view = SelectionView(frame: CGRect(origin: .zero, size: size), capture: capture, windows: windows, snappingWindows: [], screenOrigin: .zero) { _, _, _ in }
        view.showsActions = windows == nil
        view.captureOnRelease = captureOnRelease
        view.setPreviewState(selection: selection, pointer: pointer, window: windows?.first?.id)
        return view
    }
}
public extension NSScreen {
    var displayID: CGDirectDisplayID { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID() }
    static var underPointer: NSScreen? { screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? main }
}
private final class OverlayWindow: NSWindow { override var canBecomeKey: Bool { true } }
@MainActor final class SelectionView: NSView {
    private let capture: CapturedImage
    private let picture: NSImage
    private let choices: [CaptureWindow]?
    private let snappingWindows: [CaptureWindow]
    private let screenOrigin: CGPoint
    private let completion: (CGRect?, CGWindowID?, OverlayAction) -> Void
    var showsActions = false
    var captureOnRelease = false { didSet { updateAccessibilityInstructions() } }
    private var completed = false
    private var hasDragged = false
    private var freshSelection = false
    private var actionRects: [(action: OverlayAction, rect: CGRect)] = []
    private var hoveredAction: OverlayAction?
    private var start = CGPoint.zero
    private var pointer = CGPoint.zero
    private var selection = CGRect.zero
    private var selectedWindow: CGWindowID?
    private var dragging = false
    private var moving = false
    private var typedSize = ""
    private var resizeStart: CGPoint?
    private var isPreview = false
    func setPreviewState(selection: CGRect, pointer: CGPoint, window: CGWindowID?) { isPreview = true; self.selection = selection; self.pointer = pointer; selectedWindow = window }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(frame: CGRect, capture: CapturedImage, windows: [CaptureWindow]?, snappingWindows: [CaptureWindow], screenOrigin: CGPoint, completion: @escaping (CGRect?, CGWindowID?, OverlayAction) -> Void) {
        self.capture = capture; picture = NSImage(cgImage: capture.image, size: frame.size)
        choices = windows; self.snappingWindows = snappingWindows; self.screenOrigin = screenOrigin; self.completion = completion
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        updateAccessibilityInstructions()
    }
    private func updateAccessibilityInstructions() {
        let area = captureOnRelease
            ? "Area capture. Drag and release to capture. Escape cancels."
            : "Area capture. Drag to select. Arrow keys move selection. Type width x height for exact dimensions. Return captures. Escape cancels."
        setAccessibilityLabel(choices == nil ? area : "Window capture. Move over a window and click, or use Tab then Return. Escape cancels.")
    }
    private func finish(_ rect: CGRect?, _ id: CGWindowID?, _ action: OverlayAction) {
        guard !completed else { return }
        completed = true
        completion(rect, id, action)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect:bounds,options:[.mouseMoved,.activeAlways,.inVisibleRect],owner:self,userInfo:nil))
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window, !isPreview { pointer = convert(window.mouseLocationOutsideOfEventStream, from:nil) }
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    private var pixelScale: CGFloat { CGFloat(capture.image.width) / max(1, bounds.width) }

    override func draw(_ dirtyRect: NSRect) {
        picture.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        NSColor.black.withAlphaComponent(DS.overlayDim).setFill()
        let dim = NSBezierPath(rect: bounds)
        if !selection.isEmpty { dim.appendRect(selection) }
        dim.windingRule = .evenOdd; dim.fill()

        if !selection.isEmpty {
            if choices != nil {
                // Window mode: a tinted highlight with the window's name.
                let highlight = NSBezierPath(roundedRect: selection.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
                DS.nsAccent.withAlphaComponent(0.18).setFill(); highlight.fill()
                DS.nsAccent.setStroke(); highlight.lineWidth = 2; highlight.stroke()
                if let title = choices?.first(where: { $0.id == selectedWindow })?.title, !title.isEmpty {
                    badge(title, centeredAt: CGPoint(x: selection.midX, y: selection.midY), font: DS.hintFont)
                }
            } else {
                // A dark hairline under a white line stays visible on any content.
                NSColor.black.withAlphaComponent(0.35).setStroke()
                let shadow = NSBezierPath(rect: selection.insetBy(dx: -1, dy: -1)); shadow.lineWidth = 1; shadow.stroke()
                NSColor.white.setStroke()
                let outline = NSBezierPath(rect: selection); outline.lineWidth = DS.overlayLine; outline.stroke()
                if !dragging {
                    // Rule-of-thirds guides once the selection is at rest.
                    NSColor.white.withAlphaComponent(0.22).setStroke()
                    let guides = NSBezierPath(); guides.lineWidth = 0.5
                    for i in 1...2 {
                        let x = selection.minX + selection.width * CGFloat(i) / 3, y = selection.minY + selection.height * CGFloat(i) / 3
                        guides.move(to: CGPoint(x: x, y: selection.minY)); guides.line(to: CGPoint(x: x, y: selection.maxY))
                        guides.move(to: CGPoint(x: selection.minX, y: y)); guides.line(to: CGPoint(x: selection.maxX, y: y))
                    }
                    guides.stroke()
                }
                for point in corners {
                    let handle = NSBezierPath(ovalIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10))
                    NSGraphicsContext.saveGraphicsState()
                    let glow = NSShadow(); glow.shadowBlurRadius = 3; glow.shadowColor = NSColor.black.withAlphaComponent(0.45); glow.set()
                    NSColor.white.setFill(); handle.fill()
                    NSGraphicsContext.restoreGraphicsState()
                    DS.nsAccent.setStroke(); handle.lineWidth = DS.overlayLine; handle.stroke()
                }
            }
            let rect = SelectionGeometry.pixels(selection: selection, viewSize: bounds.size, imageSize: CGSize(width: capture.image.width, height: capture.image.height))
            let above = selection.minY - DS.badgeHeight - DS.sm
            badge("\(Int(rect.width)) × \(Int(rect.height))", centeredAt: CGPoint(x: selection.midX, y: (above < DS.sm ? selection.minY + DS.sm : above) + DS.badgeHeight / 2), font: DS.overlayFont)
        }
        if choices == nil && selection.isEmpty {
            NSColor.white.withAlphaComponent(0.5).setStroke()
            let cross = NSBezierPath(); cross.lineWidth = 0.5
            cross.move(to: CGPoint(x: pointer.x, y: 0)); cross.line(to: CGPoint(x: pointer.x, y: bounds.height))
            cross.move(to: CGPoint(x: 0, y: pointer.y)); cross.line(to: CGPoint(x: bounds.width, y: pointer.y)); cross.stroke()
            drawLoupe()
        }
        drawActionBar()
        let hint = choices != nil ? "Click a window   ·   esc to cancel"
            : captureOnRelease && dragging && freshSelection ? "Release to capture   ·   esc to cancel"
            : !typedSize.isEmpty ? "Size  \(typedSize)   ·   return to apply"
            : selection.isEmpty && captureOnRelease ? "Drag and release to capture   ·   esc to cancel"
            : selection.isEmpty ? "Drag to select   ·   type 800x600 for an exact size   ·   esc to cancel"
            : "return to capture   ·   space to move   ·   arrows to nudge   ·   esc to cancel"
        if actionRects.isEmpty { badge(hint, centeredAt: CGPoint(x: bounds.midX, y: bounds.maxY - DS.xxl - DS.lg), font: DS.hintFont, height: 34) }
    }

    /// A bar of one-click outcomes under a finished selection, so the choice is made at capture time.
    private func drawActionBar() {
        actionRects = []
        guard showsActions, choices == nil, !dragging, selection.width >= 8, selection.height >= 8 else { return }
        let cell = CGSize(width: 62, height: 50), inset: CGFloat = 5
        let actions = OverlayAction.allCases
        let size = CGSize(width: CGFloat(actions.count) * cell.width + inset * 2, height: cell.height + inset * 2)
        var origin = CGPoint(x: selection.midX - size.width / 2, y: selection.maxY + DS.md)
        if origin.y + size.height + DS.sm > bounds.height { origin.y = selection.minY - size.height - DS.md - DS.badgeHeight - DS.sm }
        if origin.y < DS.sm { origin.y = selection.maxY - size.height - DS.md }
        origin.x = max(DS.sm, min(origin.x, bounds.width - size.width - DS.sm))
        let bar = CGRect(origin: origin, size: size)
        NSGraphicsContext.saveGraphicsState()
        let lift = NSShadow(); lift.shadowBlurRadius = 18; lift.shadowOffset = CGSize(width: 0, height: -6); lift.shadowColor = NSColor.black.withAlphaComponent(0.45); lift.set()
        NSColor(white: 0.09, alpha: 0.94).setFill(); NSBezierPath(roundedRect: bar, xRadius: 16, yRadius: 16).fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        let border = NSBezierPath(roundedRect: bar.insetBy(dx: 0.5, dy: 0.5), xRadius: 16, yRadius: 16); border.lineWidth = 1; border.stroke()
        for (index, action) in actions.enumerated() {
            let rect = CGRect(x: bar.minX + inset + CGFloat(index) * cell.width, y: bar.minY + inset, width: cell.width, height: cell.height)
            actionRects.append((action, rect))
            let primary = action == .capture
            if primary || hoveredAction == action {
                (primary ? DS.nsAccent : NSColor.white.withAlphaComponent(0.12)).setFill()
                NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 0), xRadius: 11, yRadius: 11).fill()
            }
            let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium).applying(.init(paletteColors: [.white]))
            if let symbol = NSImage(systemSymbolName: action.symbol, accessibilityDescription: action.title)?.withSymbolConfiguration(configuration) {
                let icon = symbol.size
                symbol.draw(in: CGRect(x: rect.midX - icon.width / 2, y: rect.minY + 8 + (18 - icon.height) / 2, width: icon.width, height: icon.height),
                            from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(primary ? 1 : 0.8)]
            let label = (action.title as NSString).size(withAttributes: attributes)
            (action.title as NSString).draw(at: CGPoint(x: rect.midX - label.width / 2, y: rect.maxY - label.height - 6), withAttributes: attributes)
        }
    }

    /// A dark translucent pill with white text, kept inside the screen.
    private func badge(_ text: String, centeredAt point: CGPoint, font: NSFont, height: CGFloat = DS.badgeHeight) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let size = (text as NSString).size(withAttributes: attributes)
        let width = size.width + height * 0.9
        var rect = CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height)
        rect.origin.x = max(DS.sm, min(rect.origin.x, bounds.width - width - DS.sm))
        rect.origin.y = max(DS.sm, min(rect.origin.y, bounds.height - height - DS.sm))
        let pill = NSBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2)
        NSColor(white: 0.07, alpha: 0.86).setFill(); pill.fill()
        NSColor.white.withAlphaComponent(0.14).setStroke(); pill.lineWidth = 1; pill.stroke()
        (text as NSString).draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
    }

    /// A round magnifier showing individual pixels, the pointer position, and the color under it.
    private func drawLoupe() {
        guard !dragging else { return }
        let scale = pixelScale, count = DS.loupePixels, half = floor(count / 2)
        let center = CGPoint(x: floor(pointer.x * scale), y: floor(pointer.y * scale))
        let source = CGRect(x: center.x - half, y: center.y - half, width: count, height: count)
        let imageBounds = CGRect(x: 0, y: 0, width: capture.image.width, height: capture.image.height)
        guard imageBounds.contains(center) else { return }
        let size = DS.loupeSize, gap = DS.xl, labelHeight: CGFloat = 26
        var origin = CGPoint(x: pointer.x + gap, y: pointer.y + gap)
        if origin.x + size + DS.sm > bounds.width { origin.x = pointer.x - gap - size }
        if origin.y + size + labelHeight + DS.md > bounds.height { origin.y = pointer.y - gap - size - labelHeight }
        let rect = CGRect(origin: origin, size: CGSize(width: size, height: size))
        let circle = NSBezierPath(ovalIn: rect)

        NSGraphicsContext.saveGraphicsState()
        let lift = NSShadow(); lift.shadowBlurRadius = 14; lift.shadowOffset = CGSize(width: 0, height: -4); lift.shadowColor = NSColor.black.withAlphaComponent(0.5); lift.set()
        NSColor.black.setFill(); circle.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        circle.addClip()
        NSGraphicsContext.current?.imageInterpolation = .none
        let visible = source.intersection(imageBounds), cell = size / count
        if let image = capture.image.cropping(to: visible) {
            let target = CGRect(x: rect.minX + (visible.minX - source.minX) * cell, y: rect.minY + (visible.minY - source.minY) * cell,
                                width: visible.width * cell, height: visible.height * cell)
            NSImage(cgImage: image, size: visible.size).draw(in: target, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        }
        NSColor.black.withAlphaComponent(0.12).setStroke()
        let grid = NSBezierPath(); grid.lineWidth = 0.5
        for i in 1..<Int(count) {
            let offset = CGFloat(i) * cell
            grid.move(to: CGPoint(x: rect.minX + offset, y: rect.minY)); grid.line(to: CGPoint(x: rect.minX + offset, y: rect.maxY))
            grid.move(to: CGPoint(x: rect.minX, y: rect.minY + offset)); grid.line(to: CGPoint(x: rect.maxX, y: rect.minY + offset))
        }
        grid.stroke()
        // The pixel that will become the selection corner.
        let target = NSBezierPath(rect: CGRect(x: rect.minX + half * cell, y: rect.minY + half * cell, width: cell, height: cell))
        NSColor.white.setStroke(); target.lineWidth = 1.5; target.stroke()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.setStroke(); circle.lineWidth = 2; circle.stroke()

        var label = "\(Int(center.x)), \(Int(center.y))"
        if let pixel = capture.image.cropping(to: CGRect(x: center.x, y: center.y, width: 1, height: 1)) {
            var bytes = [UInt8](repeating: 0, count: 4)
            bytes.withUnsafeMutableBytes { buffer in
                CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            label += String(format: "   #%02X%02X%02X", bytes[0], bytes[1], bytes[2])
        }
        badge(label, centeredAt: CGPoint(x: rect.midX, y: rect.maxY + DS.sm + labelHeight / 2), font: DS.overlayFont, height: labelHeight)
    }
    override func mouseMoved(with event: NSEvent) {
        pointer = convert(event.locationInWindow,from:nil)
        hoveredAction = actionRects.first(where: { $0.rect.contains(pointer) })?.action
        if let choices {
            let point = CGPoint(x:pointer.x+screenOrigin.x,y:pointer.y+screenOrigin.y)
            if let choice = choices.first(where:{$0.frame.contains(point)}) {
                selection = choice.frame.offsetBy(dx:-screenOrigin.x,dy:-screenOrigin.y).intersection(bounds)
                selectedWindow = choice.id
            } else { selection = .zero; selectedWindow = nil }
        }
        needsDisplay = true
    }
    private var corners: [CGPoint] {
        [CGPoint(x:selection.minX,y:selection.minY),CGPoint(x:selection.maxX,y:selection.minY),CGPoint(x:selection.minX,y:selection.maxY),CGPoint(x:selection.maxX,y:selection.maxY)]
    }
    override func mouseDown(with event: NSEvent) {
        guard !completed else { return }
        let click = convert(event.locationInWindow, from: nil)
        if let hit = actionRects.first(where: { $0.rect.contains(click) }) { finish(selection, nil, hit.action); return }
        mouseMoved(with:event)
        if choices != nil { if let id = selectedWindow { finish(nil,id,.capture) }; return }
        start = pointer; dragging = true; hasDragged = false; freshSelection = false
        if !selection.isEmpty, let index = corners.firstIndex(where:{ hypot($0.x-pointer.x,$0.y-pointer.y) < DS.md }) {
            resizeStart = corners[3-index]; start = resizeStart!
        } else { resizeStart=nil; if !moving { selection = .zero; freshSelection = true } }
    }
    override func mouseDragged(with event: NSEvent) {
        guard dragging, !completed else { return }
        hasDragged = true
        let next = convert(event.locationInWindow,from:nil)
        if moving && !selection.isEmpty {
            let origin = selection.origin
            selection.origin.x += next.x-pointer.x; selection.origin.y += next.y-pointer.y
            clampSelection()
            start.x += selection.origin.x-origin.x; start.y += selection.origin.y-origin.y
        }
        else {
            var end = next
            if !event.modifierFlags.contains(.option) {
                let local = snappingWindows.map { $0.frame.offsetBy(dx:-screenOrigin.x,dy:-screenOrigin.y) }
                let xs = local.flatMap { [$0.minX,$0.maxX] }
                let ys = local.flatMap { [$0.minY,$0.maxY] }
                if let x = xs.min(by:{ abs($0-end.x)<abs($1-end.x) }), abs(x-end.x)<DS.sm { end.x=x }
                if let y = ys.min(by:{ abs($0-end.y)<abs($1-end.y) }), abs(y-end.y)<DS.sm { end.y=y }
            }
            if event.modifierFlags.contains(.shift) {
                let length = max(abs(end.x-start.x),abs(end.y-start.y))
                end = CGPoint(x:start.x+(end.x>=start.x ? length : -length),y:start.y+(end.y>=start.y ? length : -length))
            }
            selection = SelectionGeometry.rectangle(from:start,to:end,bounds:bounds)
        }
        pointer = next; needsDisplay=true
    }
    override func mouseUp(with event: NSEvent) {
        guard dragging, !completed else { return }
        // Use the final release position; AppKit can coalesce the preceding drag events.
        if hasDragged { mouseDragged(with: event) }
        dragging = false; needsDisplay = true
        if captureOnRelease, freshSelection, hasDragged, !moving, typedSize.isEmpty,
           selection.width >= 1, selection.height >= 1 {
            finish(selection, nil, .capture)
        }
    }
    override func keyDown(with event: NSEvent) {
        guard !completed else { return }
        if let choices {
            if event.keyCode == 53 { finish(nil,nil,.capture) }
            else if event.keyCode == 36, let id=selectedWindow { finish(nil,id,.capture) }
            else if [48,123,124,125,126].contains(event.keyCode), !choices.isEmpty {
                let index = (choices.firstIndex(where: { $0.id == selectedWindow }).map { $0 + 1 } ?? 0) % choices.count
                let choice = choices[index]
                selectedWindow=choice.id
                selection=choice.frame.offsetBy(dx:-screenOrigin.x,dy:-screenOrigin.y).intersection(bounds)
                setAccessibilityValue(choice.title)
            }
            needsDisplay=true; return
        }
        switch event.keyCode {
        case 53: finish(nil,nil,.capture)
        case 49: moving=true
        case 36:
            if !typedSize.isEmpty {
                let values = typedSize.split(separator:"x").compactMap { Double($0) }
                if values.count == 2, values.allSatisfy({$0>0 && $0.isFinite}) {
                    let scale = CGFloat(capture.image.width)/bounds.width
                    selection = CGRect(origin:selection.isEmpty ? pointer : selection.origin,size:CGSize(width:min(values[0]/scale,bounds.width),height:min(values[1]/scale,bounds.height)))
                    clampSelection(); typedSize=""
                }
            } else if selection.width >= 1 && selection.height >= 1 { finish(selection,nil,.capture) }
        case 123: selection.origin.x -= event.modifierFlags.contains(.shift) ? 10 : 1; clampSelection()
        case 124: selection.origin.x += event.modifierFlags.contains(.shift) ? 10 : 1; clampSelection()
        case 125: selection.origin.y += event.modifierFlags.contains(.shift) ? 10 : 1; clampSelection()
        case 126: selection.origin.y -= event.modifierFlags.contains(.shift) ? 10 : 1; clampSelection()
        case 51: if !typedSize.isEmpty { typedSize.removeLast() }
        default:
            if let characters = event.characters, characters.allSatisfy({$0.isNumber || $0 == "x"}), typedSize.count < 15 { typedSize += characters }
        }
        needsDisplay=true
    }
    override func keyUp(with event: NSEvent) { if event.keyCode == 49 { moving=false } }
    private func clampSelection() {
        selection.origin.x = max(0,min(selection.origin.x,bounds.width-selection.width))
        selection.origin.y = max(0,min(selection.origin.y,bounds.height-selection.height))
    }
}
