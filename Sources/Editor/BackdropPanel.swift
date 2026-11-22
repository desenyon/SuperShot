import SwiftUI
import AppKit
import Document
import Render
import DesignSystem

/// Left-hand panel: everything about what sits behind and around the screenshot.
struct BackdropPanel: View {
    @Bindable var model: EditorModel
    @Environment(\.colorScheme) private var scheme
    @Namespace private var selection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @LocalState private var showingPresets = false
    @LocalState private var watermarkText = ""

    private var backdrop: Backdrop { model.current.backdrop }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Backdrop").font(DS.title)
                Spacer()
                Button { showingPresets.toggle() } label: {
                    Label { Text("Presets") } icon: { Icon("stack-simple", size: DS.icon) }
                }
                .buttonStyle(QuietButtonStyle())
                .popover(isPresented: $showingPresets) { BackdropPresets(model: model) }
                IconButton("xmark", label: "Hide backdrop panel", size: DS.xl) { model.showBackdrop = false }
            }
            .padding(.horizontal, DS.panelPadding).padding(.top, DS.md).padding(.bottom, DS.sm)
            SegmentedChoice([(BackdropSection.style, "Style", nil), (.layout, "Layout", nil), (.watermark, "Watermark", nil)],
                            selection: model.backdropSection) { model.backdropSection = $0 }
                .padding(.horizontal, DS.panelPadding).padding(.bottom, DS.md)
            ViewThatFits(in: .vertical) {
                sectionContents.fixedSize(horizontal: false, vertical: true)
                ScrollView { sectionContents }.scrollIndicators(.automatic)
            }
            .animation(DS.Motion.panel(reduceMotion), value: model.backdropSection)
        }
        .frame(width: DS.backdropPanelWidth)
        .modifier(GlassSurface(radius: DS.lg))
    }

    private var sectionContents: some View {
        VStack(alignment: .leading, spacing: DS.md) {
            switch model.backdropSection {
            case .style: styleControls
            case .layout:
                if backdrop.fill != .none {
                    frameControls
                    positionControls
                } else {
                    Button("Choose a backdrop") { model.backdropSection = .style }.buttonStyle(QuietButtonStyle())
                }
                trimControls
            case .watermark: watermarkControls
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.panelPadding).padding(.bottom, DS.panelPadding)
    }

    // MARK: Fill

    private var styleControls: some View {
        Group {
            SegmentedChoice([(Backdrop.Fill.none, "None", nil), (.solid, "Color", nil), (.gradient, "Gradient", nil), (.wallpaper, "Image", nil)],
                            selection: backdrop.fill) { fill in
                if fill == .wallpaper && backdrop.wallpaper == nil { model.selectWallpaper(desktop: true) }
                if model.document.backdrop.fill != fill { model.commit { $0.backdrop.fill = fill } }
            }
            switch backdrop.fill {
            case .none: emptyState
            case .solid: solidPicker
            case .gradient: gradientPicker
            case .wallpaper: wallpaperPicker
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DS.md) {
            SectionLabel("Gradients")
            gradientGrid(Array(DS.gradients.prefix(4)))
        }
    }

    private var gradientPicker: some View {
        VStack(alignment: .leading, spacing: DS.md) {
            gradientGrid(DS.gradients)
            slider("Angle", backdrop.angle ?? 45, 0...360, suffix: "°") { $0.angle = $1 }
            HStack {
                Text("Custom").font(DS.body)
                Spacer()
                colorWell("Start color", backdrop.gradientStops.first ?? backdrop.color) { backdrop, color in
                    backdrop.color = color; backdrop.secondaryColor = backdrop.gradientStops.last ?? backdrop.secondaryColor; backdrop.stops = nil
                }
                colorWell("End color", backdrop.gradientStops.last ?? backdrop.secondaryColor) { backdrop, color in
                    backdrop.color = backdrop.gradientStops.first ?? backdrop.color; backdrop.secondaryColor = color; backdrop.stops = nil
                }
            }
        }
    }

    private func gradientGrid(_ presets: [DS.GradientPreset]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.xs), count: 4), spacing: DS.xs) {
            ForEach(presets) { preset in
                let stops = preset.hex.map { RGBA(hex: $0) }
                let selected = backdrop.fill == .gradient && backdrop.stops == stops
                Button {
                    model.commit { $0.backdrop.fill = .gradient; $0.backdrop.stops = stops; $0.backdrop.angle = preset.angle }
                } label: {
                    let points = DS.gradientPoints(angle: preset.angle)
                    let tile = RoundedRectangle(cornerRadius: DS.controlRadius, style: .continuous)
                    tile.fill(LinearGradient(colors: preset.colors, startPoint: points.0, endPoint: points.1))
                        .frame(height: DS.swatchTileHeight)
                        .overlay(tile.strokeBorder(DS.hairline(scheme)))
                        .padding(DS.insetStroke)
                        .overlay {
                            if selected {
                                RoundedRectangle(cornerRadius: DS.smallRadius).strokeBorder(DS.accent, lineWidth: DS.insetStroke)
                                    .slidingSelection("gradient", in: selection, reduceMotion: reduceMotion)
                            }
                        }
                }
                .buttonStyle(PressableStyle()).hoverLift().help(preset.name).accessibilityLabel("\(preset.name) gradient")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(-DS.insetStroke)
        .animation(DS.Motion.snappy(reduceMotion), value: backdrop.stops)
    }

    private var solidPicker: some View {
        VStack(alignment: .leading, spacing: DS.md) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.xs), count: 6), spacing: DS.xs) {
                ForEach(DS.solidHex, id: \.self) { hex in
                    let color = RGBA(hex: hex), selected = backdrop.color == color
                    Button { model.commit { $0.backdrop.color = color } } label: {
                        Circle().fill(DS.color(hex)).frame(width: 26, height: 26)
                            .overlay(Circle().strokeBorder(DS.hairline(scheme)))
                            .padding(4)
                            .overlay(Circle().strokeBorder(selected ? DS.actionInk(scheme) : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain).accessibilityLabel("Color \(color.hex)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            HStack {
                Text("Custom").font(DS.body)
                Spacer()
                Text(backdrop.color.hex).font(DS.mono).foregroundStyle(.secondary)
                colorWell("Backdrop color", backdrop.color) { $0.color = $1 }
            }
        }
    }

    private var wallpaperPicker: some View {
        VStack(alignment: .leading, spacing: DS.md) {
            HStack(spacing: DS.sm) {
                sourceTile("monitor", "Desktop") { model.selectWallpaper(desktop: true) }
                sourceTile("photo.on.rectangle.angled", "Choose…") { model.selectWallpaper() }
            }
            slider("Blur", backdrop.blur, 0...60) { $0.blur = $1 }
        }
    }
    private func sourceTile(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Icon(symbol, size: 20)
                Text(title).font(DS.caption)
            }
            .frame(maxWidth: .infinity).frame(height: 62)
            .background(DS.card(scheme), in: RoundedRectangle(cornerRadius: DS.smallRadius, style: .continuous))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    // MARK: Frame and position

    private var frameControls: some View {
        VStack(alignment: .leading, spacing: DS.md) {
            SectionLabel("Frame")
            slider("Padding", backdrop.padding, 0...320) { $0.padding = $1 }
            slider("Inset", backdrop.inset ?? 0, 0...120) { $0.inset = $1 }
            slider("Corners", backdrop.radius, 0...80) { $0.radius = $1 }
            slider("Shadow", backdrop.shadow, 0...0.8, percent: true) { $0.shadow = $1 }
        }
    }

    private var positionControls: some View {
        VStack(alignment: .leading, spacing: DS.md) {
            Hairline()
            HStack(alignment: .top, spacing: DS.lg) {
                VStack(alignment: .leading, spacing: DS.sm) {
                    SectionLabel("Align")
                    anchorPicker(CGPoint(x: backdrop.alignmentX, y: backdrop.alignmentY), selectionID: "alignment") { anchor in
                        model.commit { $0.backdrop.alignmentX = anchor.x; $0.backdrop.alignmentY = anchor.y }
                    }
                }
                VStack(alignment: .leading, spacing: DS.sm) {
                    SectionLabel("Ratio")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.xs), count: 3), spacing: DS.xs) {
                        ForEach(Self.ratios, id: \.title) { item in ratioChip(item.title, item.value) }
                    }
                }
            }
            .animation(DS.Motion.snappy(reduceMotion), value: backdrop.ratio)
            .animation(DS.Motion.snappy(reduceMotion), value: backdrop.alignmentX)
            .animation(DS.Motion.snappy(reduceMotion), value: backdrop.alignmentY)
        }
    }
    private var trimControls: some View {
        HStack(spacing: DS.sm) {
            Button("Auto-balance") { model.trim(balance: true) }.buttonStyle(QuietButtonStyle()).disabled(model.busy)
                .help("Even out blank margins around the content")
            Menu {
                Button("Trim transparent edges") { model.trim() }
                Button("Trim window shadow") { model.trim(shadow: true) }
                Button("Restore original bounds") { model.commit { $0.crop = nil } }.disabled(model.document.crop == nil)
            } label: { Text("Trim") }
                .menuStyle(.borderlessButton).fixedSize().disabled(model.busy)
        }
    }

    private var watermarkControls: some View {
        VStack(alignment: .leading, spacing: DS.md) {
            HStack(spacing: DS.sm) {
                TextField("Watermark text", text: $watermarkText)
                    .textFieldStyle(.plain).font(DS.body)
                    .padding(.horizontal, DS.sm).frame(height: DS.toolButtonSize)
                    .background(DS.card(scheme), in: RoundedRectangle(cornerRadius: DS.controlRadius))
                    .onSubmit(applyWatermark)
                    .onChange(of: watermarkText) { _, text in
                        if text.count > 120 { watermarkText = String(text.prefix(120)) }
                    }
                Button("Apply", action: applyWatermark).buttonStyle(QuietButtonStyle())
                    .disabled(watermarkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let watermark = backdrop.watermark {
                HStack(alignment: .top, spacing: DS.lg) {
                    VStack(alignment: .leading, spacing: DS.sm) {
                        SectionLabel("Position")
                        anchorPicker(watermark.anchor, selectionID: "watermark") { anchor in
                            model.commit { $0.backdrop.watermark?.anchor = anchor }
                        }
                    }
                    Button("Remove") { model.commit { $0.backdrop.watermark = nil } }
                        .buttonStyle(QuietButtonStyle())
                        .accessibilityLabel("Remove watermark")
                }
                slider("Opacity", watermark.opacity, 0.1...1, percent: true) { $0.watermark?.opacity = $1 }
            }
        }
        .onChange(of: backdrop.watermark?.text, initial: true) { _, text in watermarkText = text ?? "" }
    }

    private func applyWatermark() {
        let text = String(watermarkText.prefix(120)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        model.commit {
            var watermark = $0.backdrop.watermark ?? ImageWatermark(text: text)
            watermark.text = text
            $0.backdrop.watermark = watermark
        }
    }

    private func anchorPicker(_ current: CGPoint, selectionID: String, choose: @escaping (CGPoint) -> Void) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { column in
                        let anchor = CGPoint(x: Double(column) / 2, y: Double(row) / 2)
                        alignmentCell(anchor, selected: current == anchor, selectionID: selectionID) { choose(anchor) }
                    }
                }
            }
        }
        .padding(DS.insetStroke)
        .background(DS.card(scheme), in: RoundedRectangle(cornerRadius: DS.buttonRadius))
    }
    private static let ratios: [(title: String, value: Double)] = [
        ("Auto", 0), ("16:9", 16.0 / 9.0), ("4:3", 4.0 / 3.0), ("1:1", 1), ("3:4", 0.75), ("9:16", 9.0 / 16.0)
    ]
    private func ratioChip(_ title: String, _ ratio: Double) -> some View {
        let selected = abs(backdrop.ratio - ratio) < 0.001
        return Button { model.commit { $0.backdrop.ratio = ratio } } label: {
            Text(title).font(DS.mono).frame(maxWidth: .infinity).frame(height: DS.swatchTileHeight)
                .foregroundStyle(selected ? DS.onAccent : Color.primary)
                .background {
                    let shape = RoundedRectangle(cornerRadius: DS.controlRadius)
                    shape.fill(DS.card(scheme))
                    if selected { shape.fill(DS.accent).slidingSelection("ratio", in: selection, reduceMotion: reduceMotion) }
                }
        }
        .buttonStyle(.plain).accessibilityLabel("Aspect ratio \(title)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func alignmentCell(_ anchor: CGPoint, selected: Bool, selectionID: String, choose: @escaping () -> Void) -> some View {
        let horizontal = anchor.x == 0 ? "left" : anchor.x == 1 ? "right" : "center"
        let vertical = anchor.y == 0 ? "Top" : anchor.y == 1 ? "Bottom" : "Middle"
        return Button(action: choose) {
            Circle().fill(selected ? DS.onAccent : Color.secondary)
                .frame(width: DS.xs, height: DS.xs)
                .frame(width: DS.alignmentTarget, height: DS.alignmentTarget)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: DS.controlRadius).fill(DS.accent)
                            .slidingSelection(selectionID, in: selection, reduceMotion: reduceMotion)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel("\(vertical) \(horizontal)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Pieces

    /// Previews while dragging and records one undo step when the drag ends.
    private func slider(_ title: String, _ value: Double, _ range: ClosedRange<Double>, percent: Bool = false, suffix: String = "",
                        set: @escaping (inout Backdrop, Double) -> Void) -> some View {
        ValueSlider(title, value: value, in: range, layout: .row,
                    format: { percent ? String(format: "%.0f%%", $0 * 100) : String(format: "%.0f", $0) + suffix },
                    onChange: { value in model.previewChange { set(&$0.backdrop, value) } },
                    onEditingChanged: { editing in if !editing { model.commitDraft() } })
    }
    private func colorWell(_ label: String, _ color: RGBA, set: @escaping (inout Backdrop, RGBA) -> Void) -> some View {
        ColorPicker(label, selection: Binding(get: { Color(color.nsColor) }, set: { value in
            let next = RGBA(NSColor(value))
            model.commit { set(&$0.backdrop, next) }
        }), supportsOpacity: false).labelsHidden().fixedSize()
            .frame(width: DS.metadataIconSize, height: DS.metadataIconSize).clipShape(Circle())
            .overlay(Circle().strokeBorder(DS.hairline(scheme)).allowsHitTesting(false)).accessibilityLabel(label)
    }
}

package struct BackdropPresets: View {
    @Bindable private var model: EditorModel
    @LocalState private var naming = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    package init(model: EditorModel) { self.model = model }

    package var body: some View {
        ViewThatFits(in: .vertical) {
            presets.fixedSize(horizontal: false, vertical: true)
            ScrollView { presets }
        }
        .padding(DS.panelPadding)
        .frame(width: DS.backdropPanelWidth)
        .frame(maxHeight: DS.sidePanelWidth)
        .animation(DS.Motion.panel(reduceMotion), value: naming)
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: DS.md) {
            HStack {
                Text("Saved presets").font(DS.emphasis)
                Spacer()
                if let importPreset = model.importPresetAction {
                    IconButton("tray-arrow-down", label: "Import preset", size: DS.xl, action: importPreset)
                }
                IconButton(naming ? "xmark" : "plus", label: naming ? "Cancel new preset" : "Save current look as a preset", size: DS.xl) {
                    naming.toggle()
                }.disabled(model.savePresetAction == nil)
            }
            if naming {
                HStack(spacing: DS.sm) {
                    TextField("Preset name", text: $model.presetName)
                        .textFieldStyle(.plain).font(DS.body).padding(.horizontal, DS.sm).frame(height: DS.toolButtonSize)
                        .background(DS.card(scheme), in: RoundedRectangle(cornerRadius: DS.controlRadius, style: .continuous))
                        .onSubmit(savePreset)
                    Button("Save", action: savePreset).buttonStyle(PrimaryButtonStyle())
                        .disabled(model.presetName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if model.savedPresets.isEmpty && !naming {
                Text("No saved presets").font(DS.caption).foregroundStyle(.secondary)
            }
            ForEach(model.savedPresets) { preset in
                presetRow(preset)
            }
            HStack(spacing: DS.sm) {
                Button(model.defaultBackdrop == model.document.backdrop ? "Used for new captures" : "Use for new captures") {
                    model.saveBackdropAction?(model.document.backdrop)
                    model.defaultBackdrop = model.document.backdrop
                    model.status = "Backdrop saved for new captures"
                }
                .buttonStyle(QuietButtonStyle())
                .disabled(model.saveBackdropAction == nil || model.defaultBackdrop == model.document.backdrop)
                Button("Reset") { model.commit { $0.backdrop = Backdrop() } }.buttonStyle(QuietButtonStyle())
            }
        }
    }

    private func presetRow(_ preset: BackdropPreset) -> some View {
        let active = model.savedPresets.first { $0.backdrop == model.document.backdrop }?.id == preset.id
        let isDefault = model.savedPresets.first { $0.backdrop == model.defaultBackdrop }?.id == preset.id
        return HStack(spacing: DS.xs) {
            Button { model.commit { $0.backdrop = preset.backdrop } } label: {
                HStack(spacing: DS.sm) {
                    BackdropThumbnail(document: model.document, backdrop: preset.backdrop)
                    VStack(alignment: .leading, spacing: DS.insetStroke) {
                        Text(preset.name).font(active ? DS.emphasis : DS.body).lineLimit(1)
                        if isDefault { Text("Default").font(DS.caption).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 0)
                    if active { Icon("check", weight: .bold, size: DS.icon).foregroundStyle(DS.actionInk(scheme)) }
                }.contentShape(Rectangle())
            }.buttonStyle(PressableStyle()).accessibilityAddTraits(active ? .isSelected : [])
            if model.updatePresetAction != nil || model.exportPresetAction != nil {
                Menu {
                    if let update = model.updatePresetAction {
                        Button("Update with current look") { update(preset, model.document.backdrop) }.disabled(active)
                    }
                    if let export = model.exportPresetAction { Button("Export preset…") { export(preset) } }
                } label: { Icon("dots-three", weight: .bold, size: DS.iconSize) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("Options for \(preset.name)")
            }
        }
        .padding(DS.xs)
        .background(active ? DS.hover(scheme) : .clear, in: RoundedRectangle(cornerRadius: DS.controlRadius))
    }
    private func savePreset() {
        let name = model.presetName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        model.savePresetAction?(name, model.document.backdrop)
        model.presetName = ""; naming = false
    }
}

/// Render a named look with the same layers, crop, and renderer as the canvas.
private struct BackdropThumbnail: View {
    let document: CaptureDocument
    let backdrop: Backdrop
    @LocalState private var image: CGImage?

    var body: some View {
        Group {
            if let image { Image(decorative: image, scale: 1).resizable().scaledToFit() }
            else { Icon("image") }
        }
        .frame(width: DS.xxl, height: DS.swatchTileHeight)
        .clipShape(RoundedRectangle(cornerRadius: DS.xs))
        .task(id: document) {
            var preview = document
            preview.backdrop = backdrop
            let snapshot = preview
            let result = await Task.detached(priority: .utility) {
                let size = DocumentRenderer.layout(snapshot).size
                return try? DocumentRenderer.render(snapshot, scale: min(1, 96 / max(size.width, size.height)))
            }.value
            if !Task.isCancelled { image = result }
        }
    }
}
