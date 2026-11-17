import AppKit
import SwiftUI
import DesignSystem
import Settings

@MainActor final class PinController {
    private var windows: [PinWindow] = []
    var hasVisiblePins: Bool { windows.contains { $0.isVisible } }
    func pin(_ image: CGImage, preferences: FloatingPreferences) {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let available = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let size = PinGeometry.fittedSize(image: CGSize(width: image.width, height: image.height), longestEdge: preferences.pinSize,
                                         available: available.insetBy(dx: DS.xl, dy: DS.xl).size)
        let window = PinWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.isOpaque = false; window.backgroundColor = .clear
        window.hasShadow = preferences.pinShadow; window.level = .floating
        window.isMovableByWindowBackground = false; window.acceptsMouseMovedEvents = true
        window.collectionBehavior = preferences.pinAllSpaces ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.fullScreenAuxiliary]
        let state = PinState(image: image, window: window, initialSize: size, opacity: preferences.pinOpacity)
        window.alphaValue = state.opacity
        let host = NSHostingView(rootView: PinView(state: state)); host.sizingOptions = []; window.contentView = host
        window.setContentSize(size)
        window.setFrameOrigin(CGPoint(x: available.midX - size.width / 2, y: available.midY - size.height / 2))
        window.onClose = { [weak self, weak window] in self?.windows.removeAll { $0 === window } }
        windows.append(window)
        window.orderFrontRegardless()
    }
    func unlockAll() { windows.forEach { $0.ignoresMouseEvents = false } }
}

@MainActor private final class PinWindow: NSWindow {
    var onClose: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func close() { super.close(); onClose?() }
    override func performClose(_ sender: Any?) { close() }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "w" { close(); return true }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor @Observable final class PinState {
    let image: CGImage
    weak var window: NSWindow?
    let initialSize: CGSize
    var opacity: Double { didSet { window?.alphaValue = opacity } }
    var hovering = false
    init(image: CGImage, window: NSWindow? = nil, initialSize: CGSize? = nil, opacity: Double = 1) {
        self.image = image; self.window = window
        self.initialSize = initialSize ?? CGSize(width: image.width, height: image.height); self.opacity = opacity
    }
    func copy() { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([NSImage(cgImage: image, size: .zero)]) }
    func restoreSize() {
        guard let window else { return }
        let frame = window.frame
        let size = PinGeometry.fittedSize(image: initialSize, longestEdge: max(initialSize.width, initialSize.height), available: window.screen?.visibleFrame.size ?? initialSize)
        window.setFrame(CGRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height), display: true)
    }
}

struct PinView: View {
    @Bindable var state: PinState
    var body: some View {
        ZStack {
            Image(decorative: state.image, scale: 1).resizable().scaledToFit().allowsHitTesting(false)
            PinInteraction(state: state)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.controlRadius))
        .overlay(RoundedRectangle(cornerRadius: DS.controlRadius).strokeBorder(Color.primary.opacity(DS.outlineOpacity)).allowsHitTesting(false))
        .overlay(alignment: .top) {
            if state.hovering {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: DS.xs) {
                    Menu {
                        ForEach([1.0, 0.75, 0.5, 0.25], id: \.self) { value in
                            Button("\(Int(value * 100))%") { state.opacity = value }
                        }
                    } label: { Image(systemName: "circle.lefthalf.filled") }
                        .menuStyle(.borderlessButton).frame(width: DS.toolButton).help("Pin opacity")
                        .accessibilityLabel("Pin opacity")
                    IconButton("lock", label: "Lock pin. Unlock from the SuperShot menu.", size: DS.toolButton) { state.window?.ignoresMouseEvents = true }
                    IconButton("doc.on.doc", label: "Copy image", size: DS.toolButton) { state.copy() }
                    IconButton("xmark", label: "Close pin · ⌘W", size: DS.toolButton) { state.window?.close() }
                    }.padding(DS.xs).modifier(GlassSurface(radius: DS.controlRadius)).padding(DS.pinResizeInset)
                    Menu {
                        Button("Copy image") { state.copy() }
                        Button("Restore initial size") { state.restoreSize() }
                        Button("Lock (clicks pass through)") { state.window?.ignoresMouseEvents = true }
                        Menu("Opacity") {
                            ForEach([1.0, 0.75, 0.5, 0.25], id: \.self) { value in
                                Button("\(Int(value * 100))%") { state.opacity = value }
                            }
                        }
                        Button("Close pin") { state.window?.close() }
                    } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).frame(width: DS.toolButton)
                        .padding(DS.xs).modifier(GlassSurface(radius: DS.controlRadius)).padding(DS.xs)
                        .accessibilityLabel("Pin actions")
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "arrow.up.left.and.arrow.down.right").font(DS.caption)
                .padding(DS.xs).background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.xs))
                .padding(DS.xs).allowsHitTesting(false)
        }
        .onHover { state.hovering = $0 }
        .accessibilityLabel("Pinned screenshot")
        .accessibilityHint("Drag to move. Drag any edge to resize. Double-click to restore size. Arrow keys move; plus and minus resize.")
    }
}

private struct PinInteraction: NSViewRepresentable {
    let state: PinState
    func makeNSView(context: Context) -> PinInteractionView { PinInteractionView(state: state) }
    func updateNSView(_ view: PinInteractionView, context: Context) {}
}

private final class PinInteractionView: NSView {
    let state: PinState
    private var startFrame = CGRect.zero
    private var startPoint = CGPoint.zero
    private var edges: PinGeometry.Edges = []
    init(state: PinState) { self.state = state; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        window.makeKey(); window.makeFirstResponder(self)
        if event.clickCount == 2 { state.restoreSize(); return }
        startFrame = window.frame; startPoint = NSEvent.mouseLocation
        edges = PinGeometry.edges(at: convert(event.locationInWindow, from: nil), size: bounds.size)
        if edges.isEmpty { window.performDrag(with: event) }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window, !edges.isEmpty else { return }
        let point = NSEvent.mouseLocation
        let result = PinGeometry.resize(startFrame, edges: edges, delta: CGPoint(x: point.x - startPoint.x, y: point.y - startPoint.y),
                                        available: window.screen?.visibleFrame.size ?? startFrame.size)
        window.setFrame(result, display: true)
    }
    override func mouseUp(with event: NSEvent) { edges = [] }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
        let edge = DS.pinResizeInset
        for x in [bounds.minX, bounds.maxX - edge] { addCursorRect(CGRect(x: x, y: 0, width: edge, height: bounds.height), cursor: .resizeLeftRight) }
        for y in [bounds.minY, bounds.maxY - edge] { addCursorRect(CGRect(x: 0, y: y, width: bounds.width, height: edge), cursor: .resizeUpDown) }
    }
    override func keyDown(with event: NSEvent) {
        guard let window else { return }
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        var frame = window.frame
        switch event.keyCode {
        case 123: frame.origin.x -= step
        case 124: frame.origin.x += step
        case 125: frame.origin.y -= step
        case 126: frame.origin.y += step
        default:
            switch event.characters {
            case "+", "=", "-":
                frame = PinGeometry.resize(frame, edges: [.right, .bottom], delta: CGPoint(x: frame.width * (event.characters == "-" ? -0.1 : 0.1), y: 0), available: window.screen?.visibleFrame.size ?? frame.size)
            case "0": state.restoreSize(); return
            default: super.keyDown(with: event); return
            }
        }
        window.setFrame(frame, display: true)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        for (title, action) in [("Copy image", #selector(copyImage)), ("Restore initial size", #selector(restore)), ("Lock (clicks pass through)", #selector(lock)), ("Close pin", #selector(closePin))] {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: ""); item.target = self
        }
        return menu
    }
    @objc private func copyImage() { state.copy() }
    @objc private func restore() { state.restoreSize() }
    @objc private func lock() { window?.ignoresMouseEvents = true }
    @objc private func closePin() { window?.close() }
}
