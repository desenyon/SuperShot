import AppKit
import SwiftUI
import DesignSystem
import Settings

@MainActor final class PinController {
    private var windows: [PinWindow] = []
    /// Held over a locked pin, this key makes it clickable so it can be unlocked.
    var unlockKey: PinUnlockKey = .option { didSet { windows.forEach { $0.state?.unlockKey = unlockKey } } }
    /// Polls the pointer and modifier keys only while some pin is locked. Reading `NSEvent.modifierFlags`
    /// needs no Accessibility or Input Monitoring permission, unlike a global key monitor.
    private var unlockWatch: Timer?
    var hasVisiblePins: Bool { windows.contains { $0.isVisible } }
    func pin(_ image: CGImage, preferences: FloatingPreferences) {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let available = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let size = PinGeometry.fittedSize(image: CGSize(width: image.width, height: image.height), longestEdge: preferences.pinSize,
                                         available: available.insetBy(dx: DS.xl, dy: DS.xl).size)
        let window = PinWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.isOpaque = false; window.backgroundColor = .clear
        window.hasShadow = preferences.pinShadow; window.level = .floating
        window.isMovableByWindowBackground = false
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = preferences.pinAllSpaces ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.fullScreenAuxiliary]
        let state = PinState(image: image, window: window, initialSize: size, opacity: preferences.pinOpacity)
        state.unlockKey = unlockKey
        state.onLockChange = { [weak self] in self?.updateUnlockWatch() }
        window.state = state
        let host = NSHostingView(rootView: PinView(state: state)); host.sizingOptions = []; window.contentView = host
        window.setContentSize(size)
        window.setFrameOrigin(CGPoint(x: available.midX - size.width / 2, y: available.midY - size.height / 2))
        window.onClose = { [weak self, weak window] in self?.windows.removeAll { $0 === window }; self?.updateUnlockWatch() }
        windows.append(window)
        host.wantsLayer = true
        window.orderFrontRegardless()
        DS.Motion.present(window, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
    func unlockAll() { windows.forEach { $0.state?.locked = false } }
    func unlockUnderPointer() {
        guard let state = frontPin(at: NSEvent.mouseLocation)?.state, state.locked else { return }
        state.locked = false
    }

    private func frontPin(at pointer: CGPoint) -> PinWindow? {
        windows.filter { $0.isVisible && $0.frame.contains(pointer) }
            .min { $0.orderedIndex < $1.orderedIndex }
    }

    private func updateUnlockWatch() {
        let anyLocked = windows.contains { $0.state?.locked == true }
        if anyLocked, unlockWatch == nil {
            let timer = Timer(timeInterval: 1.0 / 15, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.checkUnlock() } }
            RunLoop.main.add(timer, forMode: .common); unlockWatch = timer
        } else if !anyLocked {
            unlockWatch?.invalidate(); unlockWatch = nil
        }
    }
    private func checkUnlock() {
        let pointer = NSEvent.mouseLocation, flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let held = flags.contains(Self.flag(unlockKey))
        let target = frontPin(at: pointer)
        for window in windows {
            guard let state = window.state, state.locked else { continue }
            let over = window === target
            if state.hinting != over { state.hinting = over }
            // Assign only on change: an @Observable write re-renders the pin even when the value is the same.
            if state.peeking != (over && held) { state.peeking = over && held }
        }
    }
    static func flag(_ key: PinUnlockKey) -> NSEvent.ModifierFlags {
        switch key { case .option: .option; case .command: .command; case .control: .control; case .shift: .shift }
    }
}

@MainActor private final class PinWindow: NSWindow {
    weak var state: PinState?
    private var closing = false
    var onClose: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func close() {
        guard !closing else { return }
        closing = true
        DS.Motion.dismiss(self, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) { [weak self] in
            self?.finishClosing()
        }
    }
    private func finishClosing() { super.close(); onClose?() }
    override func performClose(_ sender: Any?) { close() }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "w" { close(); return true }
        return super.performKeyEquivalent(with: event)
    }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        // Dragging uses global pointer coordinates. Do not constrain it to one display’s work area.
        frameRect
    }
}

@MainActor @Observable final class PinState {
    let image: CGImage
    weak var window: NSWindow?
    let initialSize: CGSize
    var opacity: Double
    var locked = false {
        didSet { window?.ignoresMouseEvents = locked; hovering = false; hinting = false; peeking = false; onLockChange?() }
    }
    var hovering = false
    /// The pointer is over this locked pin: show how to unlock it.
    var hinting = false
    /// The unlock key is held over this locked pin: it accepts clicks until the key is released.
    var peeking = false { didSet { if locked, peeking != oldValue { window?.ignoresMouseEvents = !peeking } } }
    var unlockKey: PinUnlockKey = .option
    @ObservationIgnored var onLockChange: (() -> Void)?
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

/// The badge on a locked pin. It explains the unlock key on hover and becomes an Unlock button while the key is held.
private struct PinLockBadge: View {
    @Bindable var state: PinState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Button { if state.peeking { state.locked = false } } label: {
            HStack(spacing: DS.xs + DS.xs / 2) {
                Icon(state.peeking ? "lock-simple-open" : "lock-simple", weight: .fill, size: DS.icon)
                    .contentTransition(.opacity)
                if state.peeking {
                    Text("Unlock").font(DS.caption.weight(.semibold)).transition(DS.Motion.pop(reduceMotion: reduceMotion))
                } else if state.hinting {
                    ViewThatFits(in: .horizontal) {
                        Text("Hold \(state.unlockKey.symbol), then click Unlock").fixedSize()
                        Text("Hold \(state.unlockKey.symbol)").fixedSize()
                    }
                    .font(DS.caption).transition(DS.Motion.pop(reduceMotion: reduceMotion))
                }
            }
            .foregroundStyle(state.peeking ? DS.onAccent : Color.primary)
            .padding(.horizontal, state.peeking || state.hinting ? DS.md : DS.sm).frame(height: DS.xl + DS.xs)
            .modifier(GlassSurface(radius: DS.controlRadius, tint: state.peeking ? DS.accent : nil, interactive: state.peeking))
            .contentShape(RoundedRectangle(cornerRadius: DS.controlRadius))
        }
        .buttonStyle(PressableStyle())
        .animation(DS.Motion.snappy(reduceMotion), value: state.peeking)
        .animation(DS.Motion.snappy(reduceMotion), value: state.hinting)
        .accessibilityLabel(state.peeking ? "Unlock pin" : "Pin locked. Hold \(state.unlockKey.title) over it, then choose Unlock.")
        .help(state.peeking ? "Unlock this pin" : "Hold \(state.unlockKey.title), then click Unlock")
    }
}

struct PinView: View {
    @Bindable var state: PinState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @LocalState private var adjustingOpacity = false

    var body: some View {
        ZStack {
            Image(decorative: state.image, scale: 1)
                .resizable().scaledToFit().opacity(state.opacity).allowsHitTesting(false)
            PinInteraction(state: state)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.controlRadius))
        .overlay(RoundedRectangle(cornerRadius: DS.controlRadius).strokeBorder(Color.primary.opacity(DS.outlineOpacity)).allowsHitTesting(false))
        .overlay(alignment: .topTrailing) {
            if state.locked {
                PinLockBadge(state: state).padding(DS.sm)
                    .transition(DS.Motion.pop(reduceMotion: reduceMotion))
            } else if state.hovering || adjustingOpacity {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: DS.insetStroke) {
                        IconButton("circle-half", label: "Pin opacity", selected: adjustingOpacity) { adjustingOpacity.toggle() }
                        IconButton("lock-simple-open", label: "Lock pin here · L") { state.locked = true }
                        IconButton("copy", label: "Copy image") { state.copy() }
                        IconButton("x", label: "Close pin · ⌘W") { state.window?.close() }
                    }.fixedSize()
                    Menu {
                        Button("Copy image") { state.copy() }
                        Button("Restore initial size") { state.restoreSize() }
                        Button("Lock pin here") { state.locked = true }
                        Button("Opacity…") { adjustingOpacity = true }
                        Button("Close pin") { state.window?.close() }
                    } label: {
                        Icon("dots-three", weight: .bold, size: DS.iconSize)
                            .frame(width: DS.toolButtonSize, height: DS.toolButtonSize)
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).accessibilityLabel("Pin actions")
                }
                .padding(DS.xs).modifier(GlassSurface(radius: DS.smallRadius, interactive: true))
                .popover(isPresented: $adjustingOpacity) {
                    PinOpacityControl(state: state)
                }
                .padding(DS.sm)
                .transition(DS.Motion.reveal(from: .top, reduceMotion: reduceMotion))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if state.hovering && !state.locked {
                Icon("arrows-out-simple", size: DS.md)
                    .padding(DS.xs).modifier(GlassSurface(radius: DS.controlRadius))
                    .padding(DS.xs).allowsHitTesting(false).transition(.opacity)
            }
        }
        .animation(DS.Motion.gentle(reduceMotion), value: state.opacity)
        .animation(DS.Motion.panel(reduceMotion), value: state.hovering)
        .animation(DS.Motion.snappy(reduceMotion), value: state.locked)
        .onHover { state.hovering = $0 }
        .accessibilityLabel("Pinned screenshot")
        .accessibilityHint("Drag the image to move between displays. Drag an edge to resize. Press L to lock this position.")
    }
}

struct PinOpacityControl: View {
    @Bindable var state: PinState

    var body: some View {
        VStack(alignment: .trailing, spacing: DS.sm) {
            ValueSlider("Opacity", value: state.opacity, in: 0.2...1,
                        format: { "\(Int(($0 * 100).rounded()))%" }, onChange: { state.opacity = $0 })
            Button("Reset to 100%") { state.opacity = 1 }
                .buttonStyle(QuietButtonStyle())
                .disabled(state.opacity == 1)
        }
        .padding(DS.panelPadding).frame(width: DS.pinPopoverWidth)
    }
}

private struct PinInteraction: NSViewRepresentable {
    let state: PinState
    func makeNSView(context: Context) -> PinInteractionView { PinInteractionView(state: state) }
    func updateNSView(_ view: PinInteractionView, context: Context) {}
}

@MainActor final class PinInteractionView: NSView {
    let state: PinState
    private var drag: PinGeometry.Drag?
    init(state: PinState) { self.state = state; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        guard !state.locked, let window else { return }
        window.makeKey(); window.makeFirstResponder(self)
        drag = nil
        if event.clickCount == 2 { state.restoreSize(); return }
        let pointer = window.convertPoint(toScreen: event.locationInWindow)
        let edges = PinGeometry.edges(at: convert(event.locationInWindow, from: nil), size: bounds.size)
        drag = PinGeometry.Drag(frame: window.frame, pointer: pointer, edges: edges)
    }
    override func mouseDragged(with event: NSEvent) {
        guard !state.locked, let window, let drag else { return }
        let point = NSEvent.mouseLocation
        let available = NSScreen.screens.first(where: { $0.frame.contains(point) })?.frame.size
            ?? window.screen?.frame.size ?? window.frame.size
        let next = drag.frame(at: point, available: available)
        if next.size == window.frame.size { window.setFrameOrigin(next.origin) }
        else { window.setFrame(next, display: true) }
    }
    override func mouseUp(with event: NSEvent) {
        defer { drag = nil }
        guard drag != nil, !state.locked, let window else { return }
        let reachable = PinGeometry.reachable(window.frame, on: NSScreen.screens.map(\.frame))
        if reachable.origin != window.frame.origin { window.setFrameOrigin(reachable.origin) }
    }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
        let edge = DS.pinResizeInset
        for x in [bounds.minX, bounds.maxX - edge] { addCursorRect(CGRect(x: x, y: 0, width: edge, height: bounds.height), cursor: .resizeLeftRight) }
        for y in [bounds.minY, bounds.maxY - edge] { addCursorRect(CGRect(x: 0, y: y, width: bounds.width, height: edge), cursor: .resizeUpDown) }
    }
    override func keyDown(with event: NSEvent) {
        guard !state.locked, let window else { return }
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
            case "l", "L": drag = nil; state.locked = true; return
            default: super.keyDown(with: event); return
            }
        }
        window.setFrame(PinGeometry.reachable(frame, on: NSScreen.screens.map(\.frame)), display: true)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        for (title, action) in [("Copy image", #selector(copyImage)), ("Restore initial size", #selector(restore)), ("Lock pin here", #selector(lock)), ("Close pin", #selector(closePin))] {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: ""); item.target = self
        }
        return menu
    }
    @objc private func copyImage() { state.copy() }
    @objc private func restore() { state.restoreSize() }
    @objc private func lock() { state.locked = true }
    @objc private func closePin() { window?.close() }
}
