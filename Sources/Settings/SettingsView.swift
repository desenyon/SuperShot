import SwiftUI
import AppKit
import DesignSystem
import Hotkeys
import Export
import ServiceManagement

private typealias S = DS.Preferences

public struct SettingsView: View {
    @Environment(\.colorScheme) private var scheme
    @Bindable private var store: SettingsStore
    @LocalState private var section: Section
    @LocalState private var search = ""
    @FocusState private var searchFocused: Bool
    /// Read once when the window appears; asking the system on every redraw is slow.
    @LocalState private var launchAtLogin = false
    @LocalState private var needsLoginApproval = false
    private let hasScreenAccess: Bool
    private let openPrivacy: () -> Void

    public enum Section: String, CaseIterable, Sendable {
        case general = "General", capture = "Capture", output = "Output", floating = "Pins & previews", shortcuts = "Shortcuts", library = "Library", privacy = "Privacy"
        var icon: String {
            switch self {
            case .general: "gearshape"
            case .capture: "viewfinder"
            case .output: "square.and.arrow.down"
            case .floating: "pin"
            case .shortcuts: "command"
            case .library: "square.stack"
            case .privacy: "lock.shield"
            }
        }

    }

    public init(store: SettingsStore, hasScreenAccess: Bool, initialSection: Section = .general,
                openPrivacy: @escaping () -> Void) {
        self.store = store; self.hasScreenAccess = hasScreenAccess
        self.openPrivacy = openPrivacy
        _section = LocalState(initialValue: initialSection)
    }

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
            ScrollView {
                VStack(alignment: .leading, spacing: S.sectionGap) {
                    header
                    switch section {
                    case .general: general
                    case .capture: capture
                    case .output: output
                    case .floating: floating
                    case .shortcuts: shortcuts
                    case .library: library
                    case .privacy: privacy
                    }
                    if let message = store.recoveryMessage { notice(message) }
                }
                .frame(maxWidth: S.contentWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, S.pageInset).padding(.top, S.titlebarInset).padding(.bottom, S.pageInset)
            }
            .scrollIndicators(.automatic)
            .id(section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(S.canvas(scheme))
        .tint(S.accent(scheme)).controlSize(.small)
        .ignoresSafeArea()
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled; needsLoginApproval = SMAppService.mainApp.status == .requiresApproval }
    }

    private var header: some View {
        Text(section.rawValue).font(S.title).accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var matchingSections: [Section] {
        guard !search.trimmingCharacters(in: .whitespaces).isEmpty else { return Section.allCases }
        return Section.allCases.filter { item in
            let keywords: String
            switch item {
            case .general: keywords = "appearance theme dark light system login startup dock"
            case .capture: keywords = "area window screen scrolling auto automatic copy clipboard save editor shadow cursor pointer icons sound backdrop actions enter return confirm release skip instant"
            case .output: keywords = "png jpeg heic pdf tiff webp avif format quality resolution retina color srgb file name folder location editable"
            case .floating: keywords = "thumbnail corner position dismiss timer size pin opacity transparency shadow spaces move resize"
            case .shortcuts: keywords = "keyboard hotkeys bindings profiles keys tools import export"
            case .library: keywords = "history retention days storage search"
            case .privacy: keywords = "permission recording access screen local privacy"
            }
            return (item.rawValue + " " + keywords).localizedCaseInsensitiveContains(search)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: DS.xs / 2) {
            Text("SuperShot").font(DS.emphasis)
                .padding(.horizontal, DS.sm).padding(.bottom, DS.md)
            HStack(spacing: DS.xs) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("Search settings", text: $search).textFieldStyle(.plain)
                    .focused($searchFocused).focusEffectDisabled()
                    .accessibilityLabel("Search settings")
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(SettingsButtonStyle(kind: .plain)).accessibilityLabel("Clear search")
                }
            }
            .font(S.detail).padding(.horizontal, DS.sm).frame(height: S.controlHeight)
            .background(S.fill(scheme), in: RoundedRectangle(cornerRadius: S.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: S.controlRadius)
                .strokeBorder(searchFocused ? S.accent(scheme) : .clear, lineWidth: S.focusWidth))
            .padding(.bottom, DS.sm)
            ForEach(matchingSections, id: \.self) { item in
                Button { section = item } label: {
                    HStack(spacing: DS.sm) {
                        Image(systemName: item.icon).font(S.label.weight(.regular))
                            .frame(width: DS.lg).foregroundStyle(.secondary).accessibilityHidden(true)
                        Text(item.rawValue).font(S.label)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, DS.sm).frame(height: S.navigationHeight)
                }
                .buttonStyle(SettingsButtonStyle(kind: .navigation(section == item)))
                .accessibilityAddTraits(section == item ? .isSelected : [])
            }
            if matchingSections.isEmpty {
                Text("No matching settings").font(S.detail).foregroundStyle(.secondary).padding(DS.sm)
            }
            Spacer(minLength: DS.lg)
            Button { section = .privacy } label: {
                HStack(spacing: DS.xs) {
                    Image(systemName: hasScreenAccess ? "checkmark.shield" : "exclamationmark.shield")
                        .accessibilityHidden(true)
                    Text(hasScreenAccess ? "Screen access allowed" : "Screen access needed")
                }.font(S.detail).foregroundStyle(.secondary)
            }
            .buttonStyle(SettingsButtonStyle(kind: .plain)).padding(.horizontal, DS.xs)
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.1")")
                .font(S.detail).foregroundStyle(.secondary).padding(.horizontal, DS.xs).padding(.top, DS.xs)
        }
        .padding(DS.md).padding(.top, S.titlebarInset - DS.md)
        .frame(width: S.sidebar).frame(maxHeight: .infinity)
        .background(SettingsSurface(role: .sidebar))
        .overlay(alignment: .trailing) { Rectangle().fill(S.edge(scheme)).frame(width: S.hairline) }
        .onChange(of: search) { _, _ in
            if let first = matchingSections.first, !matchingSections.contains(section) { section = first }
        }
    }

    // MARK: General

    private var general: some View {
        Group {
            group("Interface") {
                row("Appearance", "Use the system appearance or choose your own.") {
                    SettingsSegments(AppAppearance.allCases.map { ($0, $0.title) }, selection: store.preferences.appearance) {
                        store.preferences.appearance = $0
                    }.frame(width: S.controlWidth)
                }
            }
            group("Startup") {
                row("Launch at login", "Start SuperShot when you sign in.") {
                    toggle("Launch at login", Binding(get: { launchAtLogin }, set: { enabled in
                        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                        catch { store.shortcutError = error.localizedDescription }
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                        needsLoginApproval = SMAppService.mainApp.status == .requiresApproval
                    }))
                }
                if needsLoginApproval {
                    separator
                    row("Approval needed", "Allow SuperShot in Login Items.") {
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }.buttonStyle(SettingsButtonStyle())
                    }
                }
                separator
                row("Show in the Dock", "SuperShot is always available from the menu bar.") {
                    toggle("Show in the Dock", $store.preferences.showDockIcon)
                }
            }
            group("Capture preferences") {
                row("Area capture", store.preferences.areaAction.title) {
                    Button("Edit…") { section = .capture }.buttonStyle(SettingsButtonStyle())
                }
                separator
                row("Saved images", "\(ImageExport.formats.first { $0.id == store.preferences.fileFormat }?.name ?? "PNG") · \(abbreviated(store.preferences.saveFolder))") {
                    Button("Edit…") { section = .output }.buttonStyle(SettingsButtonStyle())
                }
                separator
                row("Floating captures", "Thumbnails and draggable reference images") {
                    Button("Edit…") { section = .floating }.buttonStyle(SettingsButtonStyle())
                }
            }
            if let error = store.shortcutError { notice(error) }
        }
    }

    // MARK: Capture

    private var capture: some View {
        Group {
            group("Quick capture") {
                row("Automatically copy screenshots", "Also copy to the clipboard, alongside your other capture actions.") {
                    toggle("Automatically copy screenshots", $store.preferences.autoCopyScreenshots)
                }
                separator
                row("Capture on mouse release", "Skip Enter after selecting an area. Turn off to adjust before capturing.") {
                    toggle("Capture on mouse release", $store.preferences.captureOnRelease)
                }
            }
            group("After capture", footer: "Choose any combination. Auto-copy also applies to area captures and custom actions.") {
                HStack(spacing: DS.xs) {
                    ForEach(AfterCapture.allCases, id: \.self) { action in
                        actionChoice(action, selected: store.preferences.afterCapture.contains(action)) {
                            if store.preferences.afterCapture.contains(action) { store.preferences.afterCapture.remove(action) }
                            else { store.preferences.afterCapture.insert(action) }
                        }
                    }
                }
                separator
                row("Area capture") {
                    SettingsSegments([AfterCapture.editor, .thumbnail, .copy].map { ($0, $0.shortTitle) },
                                     selection: store.preferences.areaAction) { store.preferences.areaAction = $0 }
                        .frame(width: S.controlWidth)
                }
            }
            group("What gets captured") {
                row("Include the pointer") { toggle("Include the pointer", $store.preferences.includeCursor) }
                separator
                row("Keep window shadow", "Off trims the shadow from window captures.") { toggle("Keep window shadow", $store.preferences.keepWindowShadow) }
                separator
                row("Hide desktop icons") { toggle("Hide desktop icons", $store.preferences.hideDesktopIcons) }
                separator
                row("Play a sound") { toggle("Play a sound", $store.preferences.captureSound) }
                separator
                row("Apply my backdrop", "Uses the backdrop saved with “Use for new captures” in the editor.") {
                    toggle("Apply my backdrop", $store.preferences.automaticBackdrop)
                }
            }
            group("Different actions for", footer: "Override the defaults for a capture mode.") {
                ForEach(Array(["screen", "window", "scrolling"].enumerated()), id: \.element) { index, mode in
                    if index > 0 { separator }
                    row("\(mode.capitalized) captures") {
                        toggle("Custom actions for \(mode) captures", Binding(get: { store.preferences.modeActions[mode] != nil },
                                                                             set: { store.preferences.modeActions[mode] = $0 ? store.preferences.afterCapture : nil }))
                    }
                    if store.preferences.modeActions[mode] != nil {
                        HStack(spacing: DS.xs) {
                            ForEach(AfterCapture.allCases, id: \.self) { action in modeChip(mode, action) }
                        }.padding(.top, DS.sm)
                    }
                }
            }
        }
    }
    private func actionChoice(_ action: AfterCapture, selected: Bool, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: DS.xs) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(selected ? Color.primary : Color.secondary).accessibilityHidden(true)
                Text(action.shortTitle).lineLimit(1)
            }.font(S.detail).frame(maxWidth: .infinity).frame(height: S.controlHeight)
        }
        .buttonStyle(SettingsButtonStyle(kind: .choice(selected)))
        .accessibilityLabel(action.title).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func modeChip(_ mode: String, _ action: AfterCapture) -> some View {
        let on = store.preferences.modeActions[mode]?.contains(action) == true
        return actionChoice(action, selected: on) {
            if on { store.preferences.modeActions[mode]?.remove(action) } else { store.preferences.modeActions[mode]?.insert(action) }
        }.accessibilityLabel("\(action.title) for \(mode) captures")
    }

    // MARK: Floating captures

    private var floating: some View {
        Group {
            group("Quick-access thumbnail", footer: "Drag the image into another app. Hover for copy, save, pin, and dismiss. Changes apply to your next capture.") {
                row("Screen corner") {
                    SettingsMenu(label: "Screen corner", options: ThumbnailCorner.allCases.map { ($0, $0.title) },
                                 selection: $store.preferences.floating.thumbnailCorner)
                }
                separator
                row("Dismiss after", "The timer pauses while the pointer is over the thumbnail") {
                    SettingsMenu(label: "Dismiss after", options: [(0, "Keep until dismissed")] + [5, 10, 20, 30].map { ($0, "\($0) seconds") },
                                 selection: $store.preferences.floating.thumbnailSeconds)
                }
                separator
                PreferenceSlider("Thumbnail width", value: $store.preferences.floating.thumbnailWidth, range: 200...360, unit: "pt")
            }
            group("New pins", footer: "Drag the image to move it. Drag an edge or corner to resize. Double-click to restore its initial size. Existing pins keep their own settings.") {
                PreferenceSlider("Initial size", value: $store.preferences.floating.pinSize, range: 240...1000, unit: "pt")
                separator
                PreferenceSlider("Opacity", value: $store.preferences.floating.pinOpacity, range: 0.2...1, percent: true)
                separator
                row("Show on every Space") { toggle("Show on every Space", $store.preferences.floating.pinAllSpaces) }
                separator
                row("Window shadow") { toggle("Pin window shadow", $store.preferences.floating.pinShadow) }
            }
            group("Click-through lock", footer: "Locked pins let you click the app behind them. Choose Unlock Pins in the SuperShot menu to interact with them again.") {
                HStack(spacing: DS.sm) {
                    Image(systemName: "lock").foregroundStyle(.secondary)
                    Text("Hover over a pin and choose the lock button").font(S.label)
                }
            }
        }
    }

    // MARK: Output

    private var output: some View {
        Group {
            group("Formats", footer: "PNG and TIFF are lossless; the quality setting applies to compressed formats.") {
                row("File format") {
                    SettingsMenu(label: "File format", options: ImageExport.formats.map { ($0.id, $0.name) }, selection: $store.preferences.fileFormat)
                }
                separator
                row("Clipboard format") {
                    SettingsMenu(label: "Clipboard format", options: ImageExport.formats.filter { $0.id != "com.adobe.pdf" }.map { ($0.id, $0.name) },
                                 selection: $store.preferences.clipboardFormat)
                }
                separator
                PreferenceSlider("Quality", value: $store.preferences.quality, range: 0.1...1, percent: true)
            }
            group("Image") {
                row("Resolution", "Full keeps every Retina pixel.") {
                    SettingsSegments([(false, "Full"), (true, "1×")], selection: store.preferences.oneX) { store.preferences.oneX = $0 }.frame(width: 150)
                }
                separator
                row("Color", "Display keeps the screen's full color range.") {
                    SettingsSegments([(false, "Display"), (true, "sRGB")], selection: store.preferences.convertToSRGB) { store.preferences.convertToSRGB = $0 }.frame(width: 150)
                }
                separator
                row("Save an editable copy", "Adds a .supershot file so annotations can be changed later.") { toggle("Save an editable copy", $store.preferences.saveSidecar) }
            }
            group("File name") {
                TextField("File name", text: $store.preferences.filenameTemplate)
                    .modifier(SettingsField()).accessibilityLabel("File name template")
                HStack(spacing: DS.xs) {
                    ForEach(["{date}", "{time}", "{app}", "{window}", "{counter}", "{size}"], id: \.self) { token in
                        Button { store.preferences.filenameTemplate += (store.preferences.filenameTemplate.isEmpty ? "" : " ") + token } label: {
                            Text(token).font(S.mono)
                        }.buttonStyle(SettingsButtonStyle()).help("Add \(token)").accessibilityLabel("Insert \(token) token")
                    }
                }.padding(.top, DS.sm)
                HStack(spacing: DS.sm) {
                    Text("Preview").font(S.detail).foregroundStyle(.secondary)
                    Text(exampleName).font(S.mono).lineLimit(1).truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, DS.md)
            }
            group("Location") {
                row("Save folder", abbreviated(store.preferences.saveFolder), detailLines: 1) {
                    Button("Choose…") {
                        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
                        if panel.runModal() == .OK, let url = panel.url { store.preferences.saveFolder = url.path }
                    }.buttonStyle(SettingsButtonStyle())
                }
                separator
                row("Subfolders") {
                    SettingsSegments([("none", "None"), ("date", "By date"), ("app", "By app")],
                                    selection: store.preferences.subfolders) { store.preferences.subfolders = $0 }.frame(width: S.controlWidth)
                }
            }
        }
    }
    private var exampleName: String {
        let format = ImageExport.formats.first { $0.id == store.preferences.fileFormat }
        return ImageExport.templateFilename(store.preferences.filenameTemplate, date: Date(), app: "Safari", window: "Apple", counter: store.preferences.filenameCounter,
                                            width: 1440, height: 900, extensionName: format?.extensionName ?? "png")
    }
    private func abbreviated(_ path: String) -> String { (path as NSString).abbreviatingWithTildeInPath }

    // MARK: Shortcuts

    private var shortcuts: some View {
        let presetActions = store.preferences.backdropPresets.map { (id: "preset." + $0.id.uuidString, title: "Backdrop: " + $0.name) }
        return Group {
            if let error = store.shortcutError { notice(error) }
            group("Capture", footer: "Click a shortcut, then press the new keys. Include ⌘, ⌃, or ⌥. Esc cancels.") {
                shortcutRows(Array(Shortcut.actions.prefix(9)))
            }
            group("Other") { shortcutRows(Array(Shortcut.actions.dropFirst(9)) + presetActions) }
            group("Editor tools", footer: "Single keys that switch tools while the editor is focused.") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.lg), count: 2), spacing: DS.sm) {
                    ForEach(Shortcut.editorDefaults.keys.sorted(), id: \.self) { id in editorKey(id) }
                }
            }
            group("Profiles") {
                row("Shortcut profile") {
                    HStack(spacing: DS.sm) {
                        Button("Import…") { importShortcuts() }.buttonStyle(SettingsButtonStyle())
                        Button("Export…") { exportShortcuts() }.buttonStyle(SettingsButtonStyle())
                    }
                }
                separator
                row("macOS screenshot keys", "Use ⌘⇧3, ⌘⇧4, and ⌘⇧5 for SuperShot.") {
                    Button("Set up…") { useSystemKeys() }.buttonStyle(SettingsButtonStyle())
                }
            }
            Button("Restore default shortcuts") {
                store.shortcutError = nil; store.preferences.shortcuts = Shortcut.defaults; store.preferences.toolShortcuts = [:]
            }.buttonStyle(SettingsButtonStyle())
        }
    }
    @ViewBuilder private func shortcutRows(_ actions: [(id: String, title: String)]) -> some View {
        ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
            if index > 0 { separator }
            row(action.title) {
                HStack(spacing: DS.xs) {
                    ShortcutRecorder(neutral: true, shortcut: store.preferences.shortcuts[action.id] ?? Shortcut.unassigned,
                                     recordingChanged: { store.isRecordingShortcut = $0 }) { shortcut in assign(shortcut, to: action.id) }
                        .frame(width: 124, height: S.controlHeight).accessibilityLabel("\(action.title) shortcut")
                    Button { store.preferences.shortcuts[action.id] = nil } label: {
                        Image(systemName: "xmark").font(S.detail).foregroundStyle(.secondary)
                    }
                    .buttonStyle(SettingsButtonStyle(kind: .plain)).help("Remove shortcut")
                    .accessibilityLabel("Remove \(action.title) shortcut")
                    .disabled(store.preferences.shortcuts[action.id] == nil)
                }
            }
        }
    }
    private func assign(_ shortcut: Shortcut, to id: String) {
        var proposed = store.preferences.shortcuts
        proposed[id] = shortcut
        if Shortcut.hasConflict(Array(proposed.values)) { store.shortcutError = "That shortcut is already used by another SuperShot action." }
        else { store.shortcutError = nil; store.preferences.shortcuts = proposed }
    }
    private func editorKey(_ id: String) -> some View {
        HStack {
            Text(id == "picker" ? "Color picker" : id.capitalized).font(S.label)
            Spacer()
            TextField("Key", text: Binding(get: { (store.preferences.toolShortcuts[id] ?? Shortcut.editorDefaults[id] ?? "").uppercased() }, set: { value in
                guard let key = value.lowercased().last, key.isLetter || key.isNumber else { return }
                var effective = Shortcut.editorDefaults.merging(store.preferences.toolShortcuts) { _, new in new }
                effective[id] = String(key)
                guard Set(effective.values).count == effective.count else { store.shortcutError = "That editor key is already used by another tool."; return }
                store.shortcutError = nil; store.preferences.toolShortcuts[id] = String(key)
            }))
            .multilineTextAlignment(.center).modifier(SettingsField()).frame(width: 34)
            .accessibilityLabel("\(id) tool key")
        }
    }
    private func useSystemKeys() {
        let alert = NSAlert()
        alert.messageText = "Use ⌘⇧3, ⌘⇧4, and ⌘⇧5"
        alert.informativeText = "First turn off the macOS screenshot shortcuts in System Settings → Keyboard → Keyboard Shortcuts → Screenshots. SuperShot cannot take over keys while macOS still uses them."
        alert.addButton(withTitle: "Open Keyboard Settings"); alert.addButton(withTitle: "Assign keys"); alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn, let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") { NSWorkspace.shared.open(url) }
        if response == .alertSecondButtonReturn { store.preferences.shortcuts = Shortcut.systemScreenshotPreset }
    }
    private func importShortcuts() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let profile = try JSONDecoder().decode(ShortcutProfile.self, from: Data(contentsOf: url))
            try profile.validate()
            store.preferences.shortcuts = profile.global
            store.preferences.toolShortcuts = profile.editor.mapValues { $0.lowercased() }
            store.shortcutError = nil
        } catch { store.shortcutError = error.localizedDescription }
    }
    private func exportShortcuts() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "SuperShot shortcuts.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let profile = ShortcutProfile(global: store.preferences.shortcuts,
                                          editor: Shortcut.editorDefaults.merging(store.preferences.toolShortcuts) { _, new in new })
            try JSONEncoder().encode(profile).write(to: url, options: .atomic)
        } catch { store.shortcutError = error.localizedDescription }
    }

    // MARK: Library and privacy

    private var library: some View {
        group("Capture history", footer: "Stored in Application Support on this Mac, with editable layers and searchable text. Older history is removed when a new capture is saved; exported files are never touched.") {
            row("Keep capture history", "Find previous captures in the Library.") {
                toggle("Keep capture history", $store.preferences.historyEnabled)
            }
            separator
            row("Keep captures for") {
                SettingsMenu(label: "History retention", options: [(7, "7 days"), (30, "30 days"), (90, "90 days"), (0, "Forever")],
                             selection: $store.preferences.retentionDays)
            }
        }
    }

    private var privacy: some View {
        Group {
            group("Screen Recording", footer: "macOS requires screen access before SuperShot can capture a screen, window, or area.") {
                row(hasScreenAccess ? "Access allowed" : "Access needed", hasScreenAccess ? "SuperShot can capture your screen." : "Allow SuperShot in Privacy & Security.") {
                    Button("Open Settings…", action: openPrivacy).buttonStyle(SettingsButtonStyle())
                }
            }
            group("Local processing") {
                row("No uploads", "Captures never leave this Mac unless you share them.") { EmptyView() }
                separator
                row("No analytics or accounts", "This build makes no network requests.") { EmptyView() }
                separator
                row("Accessibility only on request", "Asked for only if you turn on automatic scrolling.") { EmptyView() }
            }
        }
    }

    // MARK: Building blocks

    private func group<Content: View>(_ title: String?, footer: String? = nil, @ViewBuilder content: @escaping () -> Content) -> some View {
        SettingsGroup(title: title, footer: footer, content: content)
    }
    private func row<Control: View>(_ title: String, _ detail: String? = nil, detailLines: Int? = nil,
                                    @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: DS.md) {
            VStack(alignment: .leading, spacing: DS.xs / 2) {
                Text(title).font(S.label).fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail).font(S.detail).foregroundStyle(.secondary)
                        .lineLimit(detailLines).truncationMode(.middle).fixedSize(horizontal: false, vertical: true).help(detail)
                }
            }
            Spacer(minLength: DS.sm)
            control().fixedSize(horizontal: true, vertical: false)
        }.frame(minHeight: S.rowHeight)
    }
    private var separator: some View {
        Rectangle().fill(S.edge(scheme)).frame(height: S.hairline).padding(.vertical, DS.sm)
    }
    private func toggle(_ label: String, _ binding: Binding<Bool>) -> some View {
        SettingsToggle(label: label, isOn: binding)
    }
    private func notice(_ message: String) -> some View {
        HStack(alignment: .top, spacing: DS.sm) {
            Image(systemName: "exclamationmark.triangle").accessibilityHidden(true)
            Text(message).font(S.detail).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }.foregroundStyle(.secondary).padding(.horizontal, DS.xs)
    }
}

extension AfterCapture {
    var shortTitle: String {
        switch self { case .thumbnail: "Thumbnail"; case .copy: "Copy"; case .save: "Save"; case .editor: "Editor"; case .pin: "Pin" }
    }
}
