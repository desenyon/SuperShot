import SwiftUI
import AppKit
import QuartzCore

/// SuperShot's motion language. Every animation in the app comes from here so that panels,
/// tools, thumbnails, messages, and windows move with one consistent physical feel.
/// Springs are interruptible: a new change retargets from the current position and velocity.
/// Under Reduce Motion, movement is replaced with short crossfades, never removed silently
/// where it carries meaning (appearing, disappearing).
public extension DS {
    enum Motion {
        // MARK: Curves

        /// Selection tiles, tool switches, toggles, segmented controls. Quick, settles without overshoot.
        public static func snappy(_ reduceMotion: Bool) -> Animation {
            reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.26, dampingFraction: 0.86)
        }
        /// Panels, popovers, sheets, page changes. Smooth with a hint of follow-through.
        public static func panel(_ reduceMotion: Bool) -> Animation {
            reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.38, dampingFraction: 0.82)
        }
        /// Things that arrive: thumbnails, chat messages, toasts, the area action bar.
        public static func arrive(_ reduceMotion: Bool) -> Animation {
            reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.44, dampingFraction: 0.72)
        }
        /// Content swaps and crossfades: backdrop changes, previews, values.
        public static func gentle(_ reduceMotion: Bool) -> Animation {
            reduceMotion ? .easeOut(duration: 0.14) : .smooth(duration: 0.32)
        }
        /// A countdown ring draining one step per second. Linear on purpose: it shows elapsed time.
        public static func tick(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .linear(duration: 1) }
        /// Hover washes and highlights. Short enough to feel instant.
        public static func hover(_ reduceMotion: Bool) -> Animation { .easeOut(duration: reduceMotion ? 0.08 : 0.14) }
        /// Delay for the `index`th item of a list that appears together (menus, grids, chips).
        public static func stagger(_ index: Int, reduceMotion: Bool) -> Double { reduceMotion ? 0 : min(Double(index), 12) * 0.028 }

        // MARK: Transitions

        /// A floating panel sliding in from `edge` with a slight scale, like glass settling into place.
        public static func reveal(from edge: Edge, reduceMotion: Bool) -> AnyTransition {
            guard !reduceMotion else { return .opacity }
            let offset: CGSize = switch edge {
            case .leading: CGSize(width: -18, height: 0); case .trailing: CGSize(width: 18, height: 0)
            case .top: CGSize(width: 0, height: -12); case .bottom: CGSize(width: 0, height: 12)
            }
            return .modifier(active: RevealModifier(offset: offset, scale: 0.97, opacity: 0, blur: 6),
                             identity: RevealModifier(offset: .zero, scale: 1, opacity: 1, blur: 0))
        }
        /// Small things appearing in place: chips, badges, buttons, menus.
        public static func pop(reduceMotion: Bool) -> AnyTransition {
            reduceMotion ? .opacity : .modifier(active: RevealModifier(offset: .zero, scale: 0.9, opacity: 0, blur: 2),
                                               identity: RevealModifier(offset: .zero, scale: 1, opacity: 1, blur: 0))
        }
        /// List rows and chat messages rising into place.
        public static func rise(reduceMotion: Bool) -> AnyTransition {
            reduceMotion ? .opacity : .asymmetric(
                insertion: .modifier(active: RevealModifier(offset: CGSize(width: 0, height: 10), scale: 0.985, opacity: 0, blur: 3),
                                     identity: RevealModifier(offset: .zero, scale: 1, opacity: 1, blur: 0)),
                removal: .opacity)
        }

        // MARK: AppKit

        /// A Core Animation spring matching `arrive`, for windows and layers SwiftUI does not own.
        public static func caSpring(_ keyPath: String, from: Any?, to: Any?, reduceMotion: Bool) -> CABasicAnimation {
            if reduceMotion {
                let fade = CABasicAnimation(keyPath: keyPath); fade.fromValue = from; fade.toValue = to
                fade.duration = 0.16; fade.timingFunction = CAMediaTimingFunction(name: .easeOut); return fade
            }
            let spring = CASpringAnimation(perceptualDuration: 0.44, bounce: 0.22)
            spring.keyPath = keyPath; spring.fromValue = from; spring.toValue = to
            return spring
        }

        /// Fades and springs a borderless window into place from a slightly smaller, lower position.
        /// The window must be ordered front first; its content view must be layer-backed.
        @MainActor public static func present(_ window: NSWindow, reduceMotion: Bool) {
            guard let layer = window.contentView?.layer else { window.alphaValue = 1; return }
            window.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = reduceMotion ? 0.16 : 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1
            }
            guard !reduceMotion else { return }
            let bounds = layer.bounds
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5); layer.position = CGPoint(x: bounds.midX, y: bounds.midY)
            let start = CATransform3DTranslate(CATransform3DMakeScale(0.94, 0.94, 1), 0, -10, 0)
            let animation = caSpring("transform", from: NSValue(caTransform3D: start), to: NSValue(caTransform3D: CATransform3DIdentity), reduceMotion: false)
            layer.add(animation, forKey: "present")
        }

        /// The reverse of `present`, then orders the window out.
        @MainActor public static func dismiss(_ window: NSWindow, reduceMotion: Bool, completion: @escaping @MainActor () -> Void = {}) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = reduceMotion ? 0.12 : 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                window.animator().alphaValue = 0
                if !reduceMotion, let layer = window.contentView?.layer {
                    let shrink = CABasicAnimation(keyPath: "transform")
                    shrink.toValue = NSValue(caTransform3D: CATransform3DMakeScale(0.96, 0.96, 1))
                    shrink.duration = 0.18; shrink.fillMode = .forwards; shrink.isRemovedOnCompletion = false
                    layer.add(shrink, forKey: "dismiss")
                }
            } completionHandler: {
                MainActor.assumeIsolated { window.orderOut(nil); window.contentView?.layer?.removeAnimation(forKey: "dismiss"); completion() }
            }
        }
    }
}

/// Offset, scale, opacity, and blur in one modifier, so transitions animate them together.
struct RevealModifier: ViewModifier {
    let offset: CGSize, scale: CGFloat, opacity: Double, blur: CGFloat
    func body(content: Content) -> some View {
        content.scaleEffect(scale).offset(offset).opacity(opacity).blur(radius: blur)
    }
}

/// Buttons that press in with a quick spring and release with a little life.
public struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let scale: CGFloat
    public init(scale: CGFloat = 0.94) { self.scale = scale }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .animation(DS.Motion.snappy(reduceMotion), value: configuration.isPressed)
    }
}

public extension View {
    /// Lifts the view slightly on hover with a softer, larger shadow. For cards and thumbnails.
    func hoverLift(_ active: Bool = true) -> some View { modifier(HoverLift(active: active)) }
    /// Appears with `rise` after a staggered delay. For items in grids, lists, and chip rows.
    func staggeredAppear(_ index: Int) -> some View { modifier(StaggeredAppear(index: index)) }
}

struct HoverLift: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @LocalState private var hovering = false
    let active: Bool
    func body(content: Content) -> some View {
        let lifted = hovering && active
        content
            .scaleEffect(lifted && !reduceMotion ? 1.02 : 1)
            .offset(y: lifted && !reduceMotion ? -2 : 0)
            .shadow(color: .black.opacity(lifted ? (scheme == .dark ? 0.5 : 0.18) : 0), radius: lifted ? 18 : 0, y: lifted ? 10 : 0)
            .animation(DS.Motion.snappy(reduceMotion), value: lifted)
            .onHover { hovering = $0 }
    }
}

struct StaggeredAppear: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @LocalState private var shown = false
    let index: Int
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 8)
            .onAppear {
                guard !DS.rendersOffscreen else { shown = true; return }
                withAnimation(DS.Motion.arrive(reduceMotion).delay(DS.Motion.stagger(index, reduceMotion: reduceMotion))) { shown = true }
            }
    }
}
