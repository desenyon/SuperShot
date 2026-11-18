import SwiftUI
import AppKit
import Editor
import DesignSystem
import QuartzCore

/// Sample the shared arrival spring on the destination display's refresh clock. Window origins
/// must move with the content so its hit targets remain aligned throughout a stack rearrangement.
@MainActor class FloatingCapturePanel: NSPanel {
    private var link: CADisplayLink?
    private var origin = CGPoint.zero
    private var target = CGPoint.zero
    private var began: CFTimeInterval = 0
    private var spring: Spring?
    private var duration = 0.0
    private var initialVelocity = CGPoint.zero

    func move(to point: CGPoint, animated: Bool, velocity: CGPoint? = nil) {
        if link != nil && target == point { return }
        let currentVelocity = link.flatMap { _ in spring?.velocity(fromValue: origin, toValue: target,
                                                                  initialVelocity: initialVelocity, time: CACurrentMediaTime() - began) }
        link?.invalidate(); link = nil
        guard frame.origin != point else { return }
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard animated, !reduced, let curve = DS.Motion.caSpring("position", from: nil, to: nil, reduceMotion: false) as? CASpringAnimation else {
            setFrameOrigin(point)
            if animated && reduced { contentView?.layer?.add(DS.Motion.caSpring("opacity", from: 0.65, to: 1, reduceMotion: true), forKey: "move") }
            return
        }
        spring = Spring(mass: curve.mass, stiffness: curve.stiffness, damping: curve.damping)
        initialVelocity = velocity ?? currentVelocity ?? .zero
        origin = frame.origin; target = point; began = CACurrentMediaTime(); duration = curve.settlingDuration
        let clock = displayLink(target: self, selector: #selector(step(_:)))
        link = clock; clock.add(to: .main, forMode: .common)
    }
    @objc private func step(_ clock: CADisplayLink) {
        let elapsed = max(0, clock.targetTimestamp - began)
        guard elapsed < duration, let spring, isVisible else {
            setFrameOrigin(target); clock.invalidate(); link = nil; return
        }
        setFrameOrigin(spring.value(fromValue: origin, toValue: target, initialVelocity: initialVelocity, time: elapsed))
    }
}

@MainActor final class AskPanelController: FloatingCapturePanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    weak var anchor: ThumbnailPanel?
    var editor: EditorModel?
    var onDismiss: (() -> Void)?

    init() {
        super.init(contentRect: CGRect(origin: .zero, size: DS.Ask.panelSize), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; isReleasedWhenClosed = false
        level = .floating; hidesOnDeactivate = false; collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        setAccessibilityLabel("Ask about a capture")
    }

    func present(editor: EditorModel, beside thumbnail: ThumbnailPanel, open: @escaping () -> EditorModel) {
        guard let ask = editor.prepareAsk() else { return }
        let retarget = isVisible
        anchor = thumbnail; self.editor = editor
        let host = NSHostingView(rootView: AskView(model: ask, editor: editor, close: { [weak self] in self?.onDismiss?() }, openEditor: open))
        host.sizingOptions = []; host.wantsLayer = true; contentView = host; setContentSize(DS.Ask.panelSize)
        follow(animated: retarget)
        makeKeyAndOrderFront(nil)
        if !retarget { DS.Motion.present(self, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) }
    }

    func follow(animated: Bool) {
        guard let anchor, let screen = anchor.screen else { return }
        let visible = screen.visibleFrame
        let thumb = anchor.destination
        let x = anchor.onRight ? thumb.minX - frame.width - DS.xs : thumb.maxX + DS.xs
        let point = CGPoint(x: max(visible.minX, min(visible.maxX - frame.width, x)),
                            y: max(visible.minY, min(visible.maxY - frame.height, thumb.minY)))
        move(to: point, animated: animated)
    }

    override func cancelOperation(_ sender: Any?) { onDismiss?() }
}

@MainActor final class ThumbnailPanel: FloatingCapturePanel {
    var destination = CGRect.zero
    var onRight = true
    var swipeAway: (() -> Void)?
    private var swipe: CGFloat = 0
    private var velocity: CGFloat = 0
    private var lastTime: TimeInterval = 0
    private var trackingSwipe = false

    override func sendEvent(_ event: NSEvent) {
        guard event.type == .scrollWheel, event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else { super.sendEvent(event); return }
        if event.phase == .began { swipe = 0; velocity = 0; lastTime = event.timestamp; trackingSwipe = false }
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) { trackingSwipe = true }
        guard trackingSwipe else { super.sendEvent(event); return }
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if event.phase == .ended || event.phase == .cancelled {
            trackingSwipe = false
            if event.phase == .ended && (abs(swipe) > frame.width * 0.3 || (abs(swipe) > DS.md && abs(velocity) > 650)) {
                if !reduced { move(to: CGPoint(x: frame.minX + (swipe > 0 ? 1 : -1) * frame.width, y: frame.minY), animated: true, velocity: CGPoint(x: velocity, y: 0)) }
                swipeAway?()
            } else { move(to: destination.origin, animated: true) }
        } else {
            swipe += event.scrollingDeltaX
            if event.timestamp > lastTime && event.scrollingDeltaX != 0 { velocity = event.scrollingDeltaX / (event.timestamp - lastTime) }
            lastTime = event.timestamp
            if !reduced { setFrameOrigin(CGPoint(x: destination.minX + swipe, y: destination.minY)) }
        }
    }
}
