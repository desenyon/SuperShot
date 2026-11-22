import SwiftUI
import DesignSystem

private typealias S = DS.Preferences

struct AppearanceSettings: View {
    @Bindable var store: SettingsStore
    @Environment(\.colorScheme) private var scheme

    @Namespace private var swatches
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            SettingsGroup(title: "Theme") {
                SettingsRow("Appearance") {
                    SettingsSegments(AppAppearance.allCases.map { ($0, $0.title) }, selection: store.preferences.appearance) {
                        store.preferences.appearance = $0
                    }.frame(width: S.controlWidth)
                }
                SettingsDivider()
                SettingsRow("Accent color", store.preferences.customization.accent.title) {
                    HStack(spacing: DS.sm) {
                        ForEach(DS.AccentChoice.allCases) { choice in
                            let selected = store.preferences.customization.accent == choice
                            Button { store.preferences.customization.accent = choice } label: {
                                Circle().fill(Color(nsColor: DS.accentPalette(choice).base))
                                    .padding(DS.xs)
                                    .overlay {
                                        if selected {
                                            let ring = Circle().strokeBorder(S.accent(scheme), lineWidth: S.focusWidth)
                                            if reduceMotion { ring.transition(.opacity) }
                                            else { ring.matchedGeometryEffect(id: "swatch", in: swatches) }
                                        }
                                    }
                                    .frame(width: S.swatch + DS.xs, height: S.swatch + DS.xs)
                            }.buttonStyle(SettingsButtonStyle(kind: .plain))
                                .help(choice.title).accessibilityLabel(choice.title)
                                .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }.animation(DS.Motion.snappy(reduceMotion), value: store.preferences.customization.accent)
                }
            }
            SettingsGroup(title: "Interface", index: 1) {
                SettingsRow("Density", "Adjust the spacing between floating controls.") {
                    SettingsSegments(DS.Density.allCases.map { ($0, $0.title) }, selection: store.preferences.customization.density) {
                        store.preferences.customization.density = $0
                    }.frame(width: S.controlWidth)
                }
                SettingsDivider()
                SettingsRow("Chrome", "Use translucent glass or an opaque surface.") {
                    SettingsSegments(DS.Chrome.allCases.map { ($0, $0.title) }, selection: store.preferences.customization.chrome) {
                        store.preferences.customization.chrome = $0
                    }.frame(width: S.controlWidth)
                }
                chromePreview
            }
            SettingsGroup(title: "Toolbars", index: 2) {
                ToolbarSettings(title: "Editor tools", list: .editor, visible: $store.preferences.customization.editorTools)
                SettingsDivider()
                ToolbarSettings(title: "Area selection bar", list: .overlay, visible: $store.preferences.customization.overlayActions,
                                labels: $store.preferences.customization.overlayLabels)
                SettingsDivider()
                ToolbarSettings(title: "Thumbnail buttons", list: .thumbnail, visible: $store.preferences.customization.thumbnailActions)
            }
        }
    }

    private var chromePreview: some View {
        let customization = store.preferences.customization
        let compact = customization.density == .compact
        let tools = HStack(spacing: compact ? DS.xs : DS.md) {
            Icon("cursor", size: DS.iconSize)
            Icon("crop", size: DS.iconSize)
            Icon("pen-nib", size: DS.iconSize)
            Icon("text-t", size: DS.iconSize)
        }
        .padding(compact ? DS.xs : DS.sm)
        return ZStack {
            RoundedRectangle(cornerRadius: S.controlRadius).fill(S.fill(scheme))
            RoundedRectangle(cornerRadius: S.controlRadius).fill(S.selection(scheme))
                .frame(width: S.controlWidth, height: S.controlHeight)
                .offset(x: DS.md, y: DS.sm)
            if customization.chrome == .glass {
                tools.modifier(GlassSurface(radius: S.controlRadius))
            } else {
                tools.background(S.raised(scheme), in: RoundedRectangle(cornerRadius: S.controlRadius))
                    .overlay(RoundedRectangle(cornerRadius: S.controlRadius).strokeBorder(S.controlEdge(scheme), lineWidth: S.hairline))
            }
        }
        .frame(height: S.previewHeight)
        .animation(DS.Motion.panel(reduceMotion), value: customization.chrome)
        .animation(DS.Motion.snappy(reduceMotion), value: customization.density)
        .accessibilityHidden(true)
    }
}

private struct ToolbarSettings: View {
    let title: String
    let list: CustomizationList
    @Binding var visible: [String]
    var labels: Binding<Bool>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.settingsEditingPreview) private var editingPreview
    @LocalState private var expanded = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: DS.sm) {
            Button { withAnimation(DS.Motion.panel(reduceMotion)) { expanded.toggle() } } label: {
                HStack(spacing: DS.sm) {
                    Text(title).font(S.label)
                    Spacer()
                    Text("\(visible.count) visible").font(S.detail).foregroundStyle(.secondary)
                    Icon(expanded ? "caret-up" : "caret-down", size: DS.md)
                }.frame(maxWidth: .infinity)
            }
            .buttonStyle(SettingsButtonStyle(kind: .plain))
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            toolbarPreview.id(reduceMotion ? visible : nil).transition(.opacity)
                .animation(DS.Motion.gentle(reduceMotion), value: visible)
                .animation(DS.Motion.gentle(reduceMotion), value: labels?.wrappedValue)
            if expanded {
                if let labels {
                    SettingsRow("Show labels") { SettingsToggle(label: "Show labels", isOn: labels) }
                }
                VStack(alignment: .leading, spacing: DS.xs) {
                    ForEach(visible + list.choices.filter { !visible.contains($0) }, id: \.self) { id in
                        itemRow(id).transition(DS.Motion.pop(reduceMotion: reduceMotion))
                    }
                }.id(reduceMotion ? visible : nil).transition(.opacity)
                HStack {
                    Text("Drag the handle or use the arrows to reorder.").font(S.detail).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Reset") { visible = list.defaults; labels?.wrappedValue = true }
                        .buttonStyle(SettingsButtonStyle())
                        .accessibilityLabel("Reset \(title)")
                }
            }
        }.onAppear { if editingPreview && list == .overlay { expanded = true } }
            .padding(.vertical, DS.xs)
            .animation(DS.Motion.snappy(reduceMotion), value: visible)
    }

    private var toolbarPreview: some View {
        SettingsFlow(spacing: list == .editor ? DS.xs : DS.sm) {
            if visible.isEmpty {
                Text("No buttons shown").font(S.detail).foregroundStyle(.secondary)
            }
            ForEach(visible, id: \.self) { id in
                VStack(spacing: DS.xs) {
                    Icon(icon(id), size: DS.lg)
                    if labels?.wrappedValue == true { Text(Self.name(id)).font(S.detail) }
                }.help(Self.name(id))
            }
        }
        .padding(DS.sm).frame(maxWidth: .infinity, alignment: .leading)
        .background(S.fill(scheme), in: RoundedRectangle(cornerRadius: S.controlRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) preview")
        .accessibilityValue(visible.map(Self.name).joined(separator: ", "))
    }

    @ViewBuilder private func itemRow(_ id: String) -> some View {
        let selected = visible.contains(id)
        let name = Self.name(id)
        let pinned = list.isPinned(id)
        let row = HStack(spacing: DS.sm) {
            Button { visible = list.setting(id, visible: !selected, in: visible) } label: {
                HStack(spacing: DS.sm) {
                    Icon(selected ? "check-square" : "square", weight: selected ? .fill : .regular, size: DS.lg)
                    Icon(icon(id), size: DS.lg)
                    Text(name).font(S.label)
                }
            }
            .buttonStyle(SettingsButtonStyle(kind: .plain))
            .accessibilityLabel("Show \(name)").accessibilityValue(selected ? "On" : "Off").disabled(pinned)
            Spacer()
            if pinned {
                Text("Always shown").font(S.detail).foregroundStyle(.secondary)
            } else if selected {
                reorderControls(id, name: name)
            }
        }
        .contentShape(Rectangle())
        if selected && !pinned {
            row.dropDestination(for: String.self) { items, _ in
                    guard let payload = items.first, payload.hasPrefix(title + "/") else { return false }
                    let source = String(payload.dropFirst(title.count + 1))
                    guard visible.contains(source) else { return false }
                    visible = list.moving(source, to: id, in: visible)
                    return true
                }
                .modifier(SettingsMoveActions(item: id, items: visible.filter { !list.isPinned($0) }) { target in
                    visible = list.moving(id, to: target, in: visible)
                })
        } else { row }
    }

    private func reorderControls(_ id: String, name: String) -> some View {
        let movable = visible.filter { !list.isPinned($0) }
        let index = movable.firstIndex(of: id) ?? 0
        return HStack(spacing: DS.xs) {
            Icon("dots-six-vertical", size: DS.lg).foregroundStyle(.secondary)
                .frame(width: DS.xl, height: S.controlHeight)
                .contentShape(Rectangle())
                .help("Drag to reorder \(name)")
                .draggable("\(title)/\(id)")
                .accessibilityHidden(true)
            moveButton("caret-up", label: "Move \(name) up", to: index - 1, id: id, movable: movable)
            moveButton("caret-down", label: "Move \(name) down", to: index + 1, id: id, movable: movable)
        }
    }
    private func moveButton(_ icon: String, label: String, to index: Int, id: String, movable: [String]) -> some View {
        Button {
            guard movable.indices.contains(index) else { return }
            visible = list.moving(id, to: movable[index], in: visible)
        } label: {
            Icon(icon, size: DS.md).frame(width: DS.lg)
        }
        .buttonStyle(SettingsButtonStyle(kind: .plain))
        .disabled(!movable.indices.contains(index))
        .help(label)
        .accessibilityLabel(label)
    }

    private static func name(_ id: String) -> String {
        switch id {
        case "picker": "Color picker"
        case "drawing": "Draw"
        case "erase": "Erase with color"
        case "delete": "Dismiss"
        default: id.capitalized
        }
    }

    private func icon(_ id: String) -> String {
        switch id {
        case "select": "cursor"
        case "arrow": "arrow-up-right"
        case "oval": "circle"
        case "line": "line-segment"
        case "text": list == .overlay ? "scan" : "text-t"
        case "counter": "number-circle-one"
        case "drawing": "pen-nib"
        case "blur": "drop-half"
        case "pixelate": "grid-nine"
        case "erase": "eraser"
        case "spotlight": "flashlight"
        case "magnifier": "magnifying-glass-plus"
        case "picker": "eyedropper"
        case "capture": "camera"
        case "save": "download-simple"
        case "edit": "pencil-simple"
        case "pin": "push-pin"
        case "ask": "chat-circle-dots"
        case "delete": "x"
        default: id
        }
    }
}
