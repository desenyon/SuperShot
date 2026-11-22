import SwiftUI
import DesignSystem

@MainActor @Observable final class AskRegionGuide {
    struct Mark: Equatable {
        let rect: CGRect
        let label: String?
    }
    var mark: Mark?
}

struct AskRegionOverlay: View {
    let guide: AskRegionGuide
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        GeometryReader { canvas in
            let size = canvas.size
            if let mark = guide.mark {
                let rect = mark.rect
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: DS.xs)
                        .fill(DS.accent.opacity(DS.subtleOpacity))
                        .overlay(RoundedRectangle(cornerRadius: DS.xs).strokeBorder(DS.accent, style: StrokeStyle(lineWidth: DS.overlayLine, dash: mark.label == nil ? [] : [DS.xs, DS.xs])))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                    if let label = mark.label {
                        ForEach(0..<4) { corner in
                            RoundedRectangle(cornerRadius: DS.stroke).fill(DS.white)
                                .overlay(RoundedRectangle(cornerRadius: DS.stroke).strokeBorder(DS.accent))
                                .frame(width: DS.sm, height: DS.sm)
                                .position(x: corner % 2 == 0 ? rect.minX : rect.maxX, y: corner < 2 ? rect.minY : rect.maxY)
                        }
                        Text(label).font(DS.mono).foregroundStyle(DS.onAccent).fixedSize()
                            .padding(.horizontal, DS.sm).padding(.vertical, DS.xs)
                            .background(DS.accent, in: RoundedRectangle(cornerRadius: DS.xs))
                            .visualEffect { content, dimensions in
                                let maxX = size.width - dimensions.size.width - DS.xs
                                let toRight = rect.maxX + DS.sm
                                let toLeft = rect.minX - dimensions.size.width - DS.sm
                                let besideY = max(DS.xs, min(rect.midY - dimensions.size.height / 2, size.height - dimensions.size.height - DS.xs))
                                if toRight <= maxX || toLeft >= DS.xs {
                                    return content.offset(x: toRight <= maxX ? toRight : toLeft, y: besideY)
                                }
                                let x = max(DS.xs, min(rect.minX, maxX))
                                let y = rect.minY - dimensions.size.height - DS.sm
                                return content.offset(x: x, y: y >= DS.xs ? y : rect.maxY + DS.sm)
                            }
                    }
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .transition(DS.Motion.pop(reduceMotion: reduced))
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
        .animation(DS.Motion.snappy(reduced), value: guide.mark != nil)
    }
}

final class AskGuideHost: NSHostingView<AskRegionOverlay> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
