import DesignSystem
import SwiftUI

/// Selects pixels from the frozen frame already pinned to the conversation.
struct AskFrameRegionPicker: View {
    let image: CGImage
    let attach: (CGRect) -> Void
    @LocalState private var selection = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
    @FocusState private var focused: Bool

    private var imageSize: CGSize { CGSize(width: image.width, height: image.height) }
    private var displaySize: CGSize {
        let scale = min(DS.Ask.editorWidth / imageSize.width, (DS.Ask.panelSize.height / 2) / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }
    private var pixels: CGRect {
        selection.applying(CGAffineTransform(scaleX: imageSize.width, y: imageSize.height)).integral
            .intersection(CGRect(origin: .zero, size: imageSize))
    }
    private var dimensions: String { "\(Int(pixels.width)) × \(Int(pixels.height)) px" }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.md) {
            Text("Attach a region").font(DS.emphasis)
            Text("Drag a selection. Arrow keys move it. Hold Shift to resize.")
                .font(DS.caption).foregroundStyle(.secondary)
            frame
                .frame(maxWidth: .infinity)
            HStack {
                Text(dimensions).font(DS.mono).foregroundStyle(.secondary)
                Spacer()
                Button("Attach Region") { attach(pixels) }
                    .buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                    .disabled(pixels.isEmpty)
            }
        }
        .padding(DS.panelPadding)
        .frame(width: DS.Ask.editorWidth + DS.panelPadding * 2)
    }

    private var frame: some View {
        let size = displaySize
        let rect = selection.applying(CGAffineTransform(scaleX: size.width, y: size.height))
        return Image(decorative: image, scale: 1)
            .resizable()
            .frame(width: size.width, height: size.height)
            .overlay {
                RoundedRectangle(cornerRadius: DS.xs)
                    .fill(DS.accent.opacity(DS.subtleOpacity))
                    .overlay(RoundedRectangle(cornerRadius: DS.xs).strokeBorder(DS.accent, lineWidth: DS.overlayLine))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.controlRadius))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: DS.xs).onChanged { value in
                let start = normalized(value.startLocation, in: size)
                let end = normalized(value.location, in: size)
                selection = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                   width: max(1 / imageSize.width, abs(end.x - start.x)),
                                   height: max(1 / imageSize.height, abs(end.y - start.y)))
            })
            .focusable().focused($focused)
            .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow], phases: [.down, .repeat]) { key in
                moveSelection(key)
                return .handled
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Frame region selection").accessibilityValue(dimensions)
            .accessibilityHint("Arrow keys move the selection. Hold Shift to resize.")
            .onAppear { focused = true }
    }

    private func normalized(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: min(1, max(0, point.x / size.width)), y: min(1, max(0, point.y / size.height)))
    }

    private func moveSelection(_ key: KeyPress) {
        let step = 0.02
        let x = key.key == .leftArrow ? -step : key.key == .rightArrow ? step : 0
        let y = key.key == .upArrow ? -step : key.key == .downArrow ? step : 0
        if key.modifiers.contains(.shift) {
            selection.size.width = min(1 - selection.minX, max(1 / imageSize.width, selection.width + x))
            selection.size.height = min(1 - selection.minY, max(1 / imageSize.height, selection.height + y))
        } else {
            selection.origin.x = min(1 - selection.width, max(0, selection.minX + x))
            selection.origin.y = min(1 - selection.height, max(0, selection.minY + y))
        }
    }
}
