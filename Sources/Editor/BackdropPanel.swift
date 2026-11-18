import SwiftUI
import AppKit
import Document
import DesignSystem

/// Left-hand panel: everything about what sits behind and around the screenshot.
struct BackdropPanel: View {
    @Bindable var model: EditorModel
    @Environment(\.colorScheme) private var scheme
    @LocalState private var naming = false

    private var backdrop: Backdrop { model.current.backdrop }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Backdrop").font(DS.title)
                Spacer()
                IconButton("xmark", label: "Hide backdrop panel", size: 24) { model.showBackdrop = false }
            }
            .padding(.horizontal, DS.lg).padding(.top, DS.lg).padding(.bottom, DS.md)
            ScrollView {
                VStack(alignment: .leading, spacing: DS.lg) {
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
                    if backdrop.fill != .none {
                        frameControls
                        positionControls
                        presets
                    }
                }
                .padding(.horizontal, DS.lg).padding(.bottom, DS.lg)
            }
            .scrollIndicators(.hidden)
        }
        .frame(width: DS.backdropPanelWidth)
        .modifier(GlassSurface())
    }

    // MARK: Fill

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DS.md) {
            Text("The image exports as captured, with nothing around it.")
                .font(DS.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            SectionLabel("Quick start")
            gradientGrid(Array(DS.gradients.prefix(4)))
            Hairline()
            Button("Trim transparent edges") { model.trim() }.buttonStyle(QuietButtonStyle()).disabled(model.busy)
            Button("Trim window shadow") { model.trim(shadow: true) }.buttonStyle(QuietButtonStyle()).disabled(model.busy)
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
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.sm), count: 4), spacing: DS.sm) {
            ForEach(presets) { preset in
                let stops = preset.hex.map { RGBA(hex: $0) }
                let selected = backdrop.fill == .gradient && backdrop.stops == stops
                Button {
                    model.commit { $0.backdrop.fill = .gradient; $0.backdrop.stops = stops; $0.backdrop.angle = preset.angle }
                } label: {
                    let points = DS.gradientPoints(angle: preset.angle)
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LinearGradient(colors: preset.colors, startPoint: points.0, endPoint: points.1))
                        .frame(height: 40)
                        .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(.white.opacity(0.92)).padding(.horizontal, 11).padding(.vertical, 10)
                            .shadow(color: .black.opacity(0.25), radius: 3, y: 2))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(DS.hairline(scheme)))
                        .padding(3)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(selected ? DS.actionInk(scheme) : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain).help(preset.name).accessibilityLabel("\(preset.name) gradient")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(-3)
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
                sourceTile("desktopcomputer", "Desktop") { model.selectWallpaper(desktop: true) }
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
            Hairline()
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
                    VStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { row in
                            HStack(spacing: 3) {
                                ForEach(0..<3, id: \.self) { column in alignmentCell(row: row, column: column) }
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: DS.sm) {
                    SectionLabel("Ratio")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                        ForEach(Self.ratios, id: \.title) { item in ratioChip(item.title, item.value) }
                    }
                }
            }
            HStack(spacing: DS.sm) {
                Button("Auto-balance") { model.trim(balance: true) }.buttonStyle(QuietButtonStyle()).disabled(model.busy)
                    .help("Even out blank margins around the content")
                Menu {
                    Button("Trim transparent edges") { model.trim() }
                    Button("Trim window shadow") { model.trim(shadow: true) }
                    Button("Restore original bounds") { model.commit { $0.crop = nil } }
                } label: { Text("Trim") }
                    .menuStyle(.borderlessButton).fixedSize().disabled(model.busy)
            }
        }
    }
    private static let ratios: [(title: String, value: Double)] = [
        ("Auto", 0), ("16:9", 16.0 / 9.0), ("4:3", 4.0 / 3.0), ("1:1", 1), ("3:4", 0.75), ("9:16", 9.0 / 16.0)
    ]
    private func ratioChip(_ title: String, _ ratio: Double) -> some View {
        let selected = abs(backdrop.ratio - ratio) < 0.001
        return Button { model.commit { $0.backdrop.ratio = ratio } } label: {
            Text(title).font(DS.caption).frame(maxWidth: .infinity).frame(height: 24)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? DS.accent : DS.card(scheme), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain).accessibilityLabel("Aspect ratio \(title)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func alignmentCell(row: Int, column: Int) -> some View {
        let x = Double(column) / 2, y = Double(row) / 2
        let selected = backdrop.alignmentX == x && backdrop.alignmentY == y
        return Button { model.commit { $0.backdrop.alignmentX = x; $0.backdrop.alignmentY = y } } label: {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(selected ? DS.accent : DS.card(scheme))
                .frame(width: 24, height: 18)
        }
        .buttonStyle(.plain).accessibilityLabel("Align row \(row + 1), column \(column + 1)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Presets

    private var presets: some View {
        VStack(alignment: .leading, spacing: DS.md) {
            Hairline()
            HStack {
                SectionLabel("Presets")
                Spacer()
                Button { naming.toggle() } label: { Icon(naming ? "xmark" : "plus", weight: .bold, size: 13) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Save the current backdrop as a preset")
            }
            if naming {
                HStack(spacing: DS.sm) {
                    TextField("Preset name", text: $model.presetName)
                        .textFieldStyle(.plain).font(DS.body).padding(.horizontal, DS.sm).frame(height: 28)
                        .background(DS.card(scheme), in: RoundedRectangle(cornerRadius: DS.controlRadius, style: .continuous))
                        .onSubmit(savePreset)
                    Button("Save", action: savePreset).buttonStyle(PrimaryButtonStyle())
                        .disabled(model.presetName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if model.savedPresets.isEmpty && !naming {
                Text("Save a look you like and reuse it. Presets can have their own shortcut in Settings.")
                    .font(DS.caption).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(model.savedPresets) { preset in
                Button { model.commit { $0.backdrop = preset.backdrop } } label: {
                    HStack(spacing: DS.sm) {
                        presetSwatch(preset.backdrop)
                        Text(preset.name).font(DS.body).lineLimit(1)
                        Spacer()
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            HStack(spacing: DS.sm) {
                Button("Use for new captures") { model.saveBackdropAction?(model.document.backdrop); model.status = "Backdrop saved for new captures" }
                    .buttonStyle(QuietButtonStyle()).disabled(model.saveBackdropAction == nil)
                Button("Reset") { model.commit { $0.backdrop = Backdrop() } }.buttonStyle(QuietButtonStyle())
            }
        }
    }
    private func savePreset() {
        let name = model.presetName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        model.savePresetAction?(name, model.document.backdrop)
        model.presetName = ""; naming = false
    }
    private func presetSwatch(_ backdrop: Backdrop) -> some View {
        let points = DS.gradientPoints(angle: backdrop.angle ?? 45)
        let colors = backdrop.fill == .gradient ? backdrop.gradientStops.map { Color($0.nsColor) } : [Color(backdrop.color.nsColor)]
        return RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(LinearGradient(colors: colors.count > 1 ? colors : colors + colors, startPoint: points.0, endPoint: points.1))
            .frame(width: 28, height: 20)
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(DS.hairline(scheme)))
    }

    // MARK: Pieces

    /// Previews while dragging and records one undo step when the drag ends.
    private func slider(_ title: String, _ value: Double, _ range: ClosedRange<Double>, percent: Bool = false, suffix: String = "",
                        set: @escaping (inout Backdrop, Double) -> Void) -> some View {
        ValueSlider(title, value: value, in: range,
                    format: { percent ? String(format: "%.0f%%", $0 * 100) : String(format: "%.0f", $0) + suffix },
                    onChange: { value in model.previewChange { set(&$0.backdrop, value) } },
                    onEditingChanged: { editing in if !editing { model.commitDraft() } })
    }
    private func colorWell(_ label: String, _ color: RGBA, set: @escaping (inout Backdrop, RGBA) -> Void) -> some View {
        ColorPicker(label, selection: Binding(get: { Color(color.nsColor) }, set: { value in
            let next = RGBA(NSColor(value))
            model.commit { set(&$0.backdrop, next) }
        }), supportsOpacity: false).labelsHidden().frame(width: 30)
    }
}
