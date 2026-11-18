import SwiftUI
import AppKit
import Document
import DesignSystem

/// Contextual options for the active tool or the selected layer. Hidden when there is nothing to adjust.
struct ToolOptionsBar: View {
    @Bindable var model: EditorModel
    @Environment(\.colorScheme) private var scheme

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The kind being styled: the selected layer wins over the active tool.
    private var kind: LayerKind? { model.selectedLayer?.kind ?? ToolRegistry.tool(model.tool)?.kind }

    var body: some View {
        Group {
            if model.tool == "crop" { bar { cropOptions } }
            else if model.tool == "picker" { bar { pickerOptions } }
            else if model.tool == "liveText" { bar { liveTextOptions } }
            else if let kind { bar { styleOptions(kind) } }
        }
        .animation(DS.Motion.panel(reduceMotion), value: model.tool)
        .animation(DS.Motion.panel(reduceMotion), value: kind)
    }

    private func bar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: DS.sm) { content() }.id(kind?.rawValue ?? model.tool).transition(.opacity)
            .padding(.horizontal, DS.md).frame(height: DS.capsuleHeight)
            .modifier(GlassSurface(radius: DS.pill))
            .transition(DS.Motion.reveal(from: .top, reduceMotion: reduceMotion))
    }

    // MARK: Per-mode content

    private var cropOptions: some View {
        Group {
            hint("crop", "Drag on the image to crop")
            divider
            Button("Trim edges") { model.trim() }.buttonStyle(QuietButtonStyle()).disabled(model.busy)
            Button("Auto-balance") { model.trim(balance: true) }.buttonStyle(QuietButtonStyle()).disabled(model.busy)
            if model.document.crop != nil {
                Button("Reset crop") { model.commit { $0.crop = nil } }.buttonStyle(QuietButtonStyle())
            }
        }
    }

    private var pickerOptions: some View {
        Group {
            Circle().fill(Color(model.style.color.nsColor)).frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(DS.hairline(scheme)))
            Text(model.style.color.hex).font(DS.mono)
            divider
            SegmentedChoice([("hex", "Hex", nil), ("rgb", "RGB", nil), ("hsl", "HSL", nil), ("p3", "P3", nil)],
                            selection: model.colorFormat) { model.colorFormat = $0 }
                .frame(width: 200)
            hint(nil, "Click a pixel to copy its color")
        }
    }

    private var liveTextOptions: some View {
        Group {
            hint("text.viewfinder", "Click highlighted text to copy it")
            divider
            if let result = model.recognition {
                Button("Copy all") { model.copyText(result.transcript) }.buttonStyle(QuietButtonStyle())
            }
            Button("Done") { model.tool = "select" }.buttonStyle(QuietButtonStyle())
        }
    }

    @ViewBuilder private func styleOptions(_ kind: LayerKind) -> some View {
        let usesColor = ![.blur, .pixelate, .spotlight, .erase, .image].contains(kind)
        let usesStroke = [.rectangle, .oval, .line, .arrow, .drawing, .highlighter, .magnifier, .ruler].contains(kind)
        if usesColor { colors; divider }
        if usesStroke {
            slider("Size", model.selectedLayer?.stroke ?? model.style.stroke, 1...24) { value, live in
                model.restyle(live: live, { $0.stroke = value }, layers: { $0.stroke = value })
            }
        }
        if kind == .blur || kind == .pixelate {
            slider("Strength", model.selectedLayer?.stroke ?? model.style.stroke, 1...24) { value, live in
                model.restyle(live: live, { $0.stroke = value }, layers: { $0.stroke = value })
            }
        }
        if kind == .text || kind == .counter {
            slider("Size", model.selectedLayer?.fontSize ?? model.style.fontSize, 12...120) { value, live in
                model.restyle(live: live, { $0.fontSize = value }, layers: { $0.fontSize = value })
            }
        }
        if kind == .rectangle || kind == .oval {
            let filled = model.selectedLayer?.filled ?? model.style.filled
            IconButton(filled ? "square.fill" : "square", label: filled ? "Filled shape" : "Outlined shape", selected: filled) {
                model.restyle({ $0.filled = !filled }, layers: { $0.filled = !filled })
            }
        }
        if kind == .arrow { arrowOptions }
        if kind == .text { textOptions }
        if usesColor || kind == .image {
            slider("Opacity", model.selectedLayer?.opacity ?? model.style.opacity, 0.05...1, percent: true) { value, live in
                model.restyle(live: live, { $0.opacity = value }, layers: { $0.opacity = value })
            }
        }
        if kind == .erase { hint(nil, "Fills with the color next to where you start") }
        if kind == .spotlight { hint(nil, "Drag over the area to keep bright") }
        if model.selectedLayer != nil { divider; arrangement }
    }

    private var colors: some View {
        let current = model.selectedLayer?.color ?? model.style.color
        return HStack(spacing: DS.insetStroke) {
            ForEach(0..<DS.annotationColors.count, id: \.self) { index in
                let color = RGBA(DS.annotationColors[index])
                Button { model.restyle({ $0.color = color }, layers: { $0.color = color }) } label: {
                    Circle().fill(Color(DS.annotationColors[index])).frame(width: DS.swatchDiameter, height: DS.swatchDiameter)
                        .overlay(Circle().strokeBorder(DS.hairline(scheme)))
                        .padding(DS.xs)
                        .overlay(Circle().strokeBorder(current == color ? DS.actionInk(scheme) : .clear, lineWidth: DS.insetStroke))
                }
                .buttonStyle(.plain).accessibilityLabel("Color \(color.hex)")
                .accessibilityAddTraits(current == color ? .isSelected : [])
            }
            ColorPicker("Custom color", selection: Binding(get: { Color(current.nsColor) }, set: { value in
                let color = RGBA(NSColor(value))
                model.restyle({ $0.color = color }, layers: { $0.color = color })
            })).labelsHidden().fixedSize()
                .frame(width: DS.swatchDiameter, height: DS.swatchDiameter).clipShape(Circle())
                .overlay(Icon("plus", weight: .bold, size: DS.md).foregroundStyle(DS.white).shadow(radius: DS.insetStroke).allowsHitTesting(false))
                .padding(DS.xs).help("Custom color").accessibilityLabel("Custom color")
        }
    }

    private var arrowOptions: some View {
        let head = model.selectedLayer?.arrowHead ?? model.style.arrowHead
        return Group {
            Menu {
                ForEach([("filled", "Solid head"), ("open", "Open head"), ("double", "Both ends"), ("none", "No head")], id: \.0) { value, title in
                    Button { model.restyle({ $0.arrowHead = value }, layers: { $0.arrowHead = value }) } label: {
                        if head == value { Label(title, systemImage: "checkmark") } else { Text(title) }
                    }
                }
            } label: { Icon("arrow.up.right", size: DS.iconSize).frame(width: DS.toolButtonSize, height: DS.toolButtonSize) }
                .menuStyle(.borderlessButton).fixedSize().help("Arrowhead style")
            slider("Curve", model.selectedLayer?.arrowBend ?? model.style.arrowBend, -0.6...0.6, decimals: true) { value, live in
                model.restyle(live: live, { $0.arrowBend = value }, layers: { $0.arrowBend = value })
            }
        }
    }

    private var textOptions: some View {
        let background = model.selectedLayer.map { $0.textBackground != nil } ?? model.style.textBackground
        let outline = model.selectedLayer?.textOutline ?? model.style.textOutline
        return Group {
            IconButton("character.textbox", label: "Text background", selected: background) {
                model.restyle({ $0.textBackground = !background }, layers: { $0.textBackground = background ? nil : .black })
            }
            IconButton("a.square", label: "Text outline", selected: outline) {
                model.restyle({ $0.textOutline = !outline }, layers: { $0.textOutline = !outline })
            }
            if let layer = model.selectedLayer, layer.kind == .text {
                TextField("Text", text: Binding(get: { layer.text }, set: { text in model.modifySelected { $0.text = text } }))
                    .textFieldStyle(.plain).font(DS.body).padding(.horizontal, DS.sm).frame(width: 140, height: 26)
                    .background(DS.card(scheme), in: RoundedRectangle(cornerRadius: DS.controlRadius, style: .continuous))
            }
        }
    }

    private var arrangement: some View {
        HStack(spacing: DS.insetStroke) {
            Menu {
                Button("Rotate 15° left") { model.modifySelected { $0.rotation -= 15 } }
                Button("Rotate 15° right") { model.modifySelected { $0.rotation += 15 } }
                Button("Rotate 90°") { model.modifySelected { $0.rotation += 90 } }
                Divider()
                Button("Reset rotation") { model.modifySelected { $0.rotation = 0 } }
            } label: { Icon("rotate.right", size: DS.iconSize).frame(width: DS.toolButtonSize, height: DS.toolButtonSize) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Rotate")
            IconButton("square.3.layers.3d.top.filled", label: "Bring to front", size: DS.toolButtonSize) { model.reorderSelected(front: true) }
            IconButton("square.3.layers.3d.bottom.filled", label: "Send to back", size: DS.toolButtonSize) { model.reorderSelected(front: false) }
            IconButton("trash", label: "Delete · ⌫", size: DS.toolButtonSize) { model.deleteSelection() }
        }
    }

    // MARK: Pieces

    private func slider(_ title: String, _ value: Double, _ range: ClosedRange<Double>, percent: Bool = false, decimals: Bool = false,
                        change: @escaping (Double, Bool) -> Void) -> some View {
        ValueSlider(title, value: value, in: range, compact: true,
                    format: { percent ? String(format: "%.0f%%", $0 * 100) : decimals ? String(format: "%.1f", $0) : String(format: "%.0f", $0) },
                    onChange: { change($0, true) },
                    onEditingChanged: { editing in if !editing { model.commitDraft() } })
    }
    private func hint(_ symbol: String?, _ text: String) -> some View {
        HStack(spacing: 6) {
            if let symbol { Icon(symbol, size: 14) }
            Text(text).font(DS.caption)
        }.foregroundStyle(.secondary)
    }
    private var divider: some View { Rectangle().fill(DS.hairline(scheme)).frame(width: DS.stroke, height: DS.iconSize) }
}
