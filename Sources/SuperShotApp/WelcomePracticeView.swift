import SwiftUI
import DesignSystem

/// The sample is drawn locally. Dragging only selects its illustration and never reads the display.
struct WelcomePracticeView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var draft: CGRect?
    @LocalState private var introPresented = false
    let step: WelcomeStep
    @Binding var selection: CGRect?
    let compact: Bool

    private typealias S = DS.Preferences
    private var canvasRatio: CGFloat { compact ? 2.1 : 1.46 }
    private var isPractice: Bool { step == .practice }
    private var activeSelection: CGRect? {
        switch step {
        case .intro: introPresented || DS.rendersOffscreen ? WelcomeSelection.example : nil
        case .practice: draft ?? selection
        case .access: selection ?? WelcomeSelection.example
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.sm) {
                Icon("image", size: DS.iconSize)
                Text("Contour study").font(DS.emphasis)
                Spacer(minLength: DS.sm)
                Text(isPractice && selection != nil ? "Region selected" : "Sample image")
                    .font(DS.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, DS.md)
            .frame(minHeight: S.rowHeight)
            .accessibilityHidden(true)
            GeometryReader { geometry in
                sample(geometry.size)
            }
            .aspectRatio(canvasRatio, contentMode: .fit)
        }
        .background(S.groupFallback(scheme))
        .clipShape(RoundedRectangle(cornerRadius: DS.lg))
        .overlay(RoundedRectangle(cornerRadius: DS.lg).strokeBorder(S.edge(scheme), lineWidth: DS.stroke))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sample image, Contour study")
        .accessibilityValue(activeSelection == nil ? "No region selected" : "Region selected")
        .onAppear {
            guard !DS.rendersOffscreen else { return }
            withAnimation(DS.Motion.arrive(reduceMotion)) { introPresented = true }
        }
    }

    private func sample(_ size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            WelcomeContourArt()
            if let rect = activeSelection {
                WelcomeMarquee(
                    rect: CGRect(
                        x: rect.minX * size.width, y: rect.minY * size.height,
                        width: rect.width * size.width, height: rect.height * size.height
                    )
                )
                .transition(DS.Motion.pop(reduceMotion: reduceMotion))
            }
        }
        .contentShape(Rectangle())
        .gesture(selectionDrag(in: size), including: isPractice ? .gesture : .none)
        .clipped()
    }

    private func selectionDrag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: DS.xs)
            .updating($draft) { value, draft, _ in
                draft = WelcomeSelection.normalized(from: value.startLocation, to: value.location, in: size, minimum: DS.xs)
            }
            .onEnded { value in
                if let rect = WelcomeSelection.normalized(from: value.startLocation, to: value.location, in: size, minimum: DS.sm) {
                    selection = rect
                }
            }
    }
}

private struct WelcomeMarquee: View {
    let rect: CGRect
    var body: some View {
        Canvas { context, size in
            let shade = Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                path.addRect(rect)
            }
            context.fill(shade, with: .color(DS.black.opacity(DS.shadowOpacity)), style: FillStyle(eoFill: true))
            context.stroke(Path(rect), with: .color(DS.black.opacity(DS.shadowOpacity)), lineWidth: DS.xs / 2)
            context.stroke(Path(rect), with: .color(DS.accent), lineWidth: DS.stroke)
            for point in [
                CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)
            ] {
                let edge = DS.xs + DS.stroke
                let handle = CGRect(x: point.x - edge / 2, y: point.y - edge / 2, width: edge, height: edge)
                context.fill(Path(handle), with: .color(DS.onAccent))
                context.stroke(Path(handle), with: .color(DS.accent), lineWidth: DS.stroke)
            }
        }
        .allowsHitTesting(false)
    }
}

/// An original contour map gives the sample a detailed subject that makes an area selection meaningful.
private struct WelcomeContourArt: View {
    @Environment(\.colorScheme) private var scheme
    private typealias S = DS.Preferences

    var body: some View {
        Canvas { context, size in
            let tone = Color.primary
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(S.sidebarFallback(scheme)))
            let grid = Path { path in
                let cell = DS.xl
                for x in stride(from: cell, to: size.width, by: cell) {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                for y in stride(from: cell, to: size.height, by: cell) {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
            }
            context.stroke(grid, with: .color(S.fill(scheme)), lineWidth: DS.stroke)

            for index in (0..<12).reversed() {
                let level = CGFloat(index)
                let path = contour(in: size, level: level)
                context.fill(path, with: .color(tone.opacity(index.isMultiple(of: 3) ? 0.027 : 0.012)))
                context.stroke(path, with: .color(tone.opacity(index.isMultiple(of: 3) ? 0.31 : 0.18)), lineWidth: DS.stroke)
            }
            let trail = Path { path in
                path.move(to: CGPoint(x: size.width * 0.05, y: size.height * 0.85))
                path.addQuadCurve(to: CGPoint(x: size.width * 0.31, y: size.height * 0.66),
                                  control: CGPoint(x: size.width * 0.12, y: size.height * 0.65))
                path.addQuadCurve(to: CGPoint(x: size.width * 0.60, y: size.height * 0.35),
                                  control: CGPoint(x: size.width * 0.46, y: size.height * 0.68))
                path.addQuadCurve(to: CGPoint(x: size.width * 0.93, y: size.height * 0.15),
                                  control: CGPoint(x: size.width * 0.62, y: size.height * 0.20))
            }
            context.stroke(trail, with: .color(tone.opacity(0.64)), style: StrokeStyle(lineWidth: DS.stroke, dash: [DS.xs, DS.xs]))
        }
    }

    private func contour(in size: CGSize, level: CGFloat) -> Path {
        let radius = 0.052 + level * 0.035
        return Path { path in
            for index in 0...112 {
                let angle = 2 * CGFloat.pi * CGFloat(index) / 112
                let offset = cos(angle * 3 + 0.7) * 0.15 + sin(angle * 5 - level * 0.13) * 0.09
                let x = size.width * (0.50 + level * 0.004 + cos(angle) * radius * (1 + offset))
                let y = size.height * (0.49 - level * 0.003 + sin(angle) * radius * (1.10 + offset) - cos(angle) * radius * 0.22)
                if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            path.closeSubpath()
        }
    }
}
