import SwiftUI
import AppKit
import DesignSystem
import Hotkeys
import AI
import Export
import ServiceManagement

private typealias S = DS.Preferences

public struct SettingsView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var navigation
    @LocalState private var visited: Set<Section> = []
    @Bindable private var store: SettingsStore
    @LocalState private var section: Section
    @LocalState private var search = ""
    @FocusState private var searchFocused: Bool
    /// Read once when the window appears; asking the system on every redraw is slow.
    @LocalState private var launchAtLogin = false
    @LocalState private var needsLoginApproval = false
    private let hasScreenAccess: Bool
    private let assistantService: (AssistantProvider) -> any AssistantService
    private let openPrivacy: () -> Void

    public enum Section: String, CaseIterable, Sendable {
        case general = "General", appearance = "Appearance", capture = "Capture", output = "Output", floating = "Pins & previews", shortcuts = "Shortcuts", library = "Library", privacy = "Privacy", assistant = "Assistant"
        var icon: String {
            switch self {
            case .general: "gear-six"
            case .appearance: "palette"
            case .assistant: "chat-circle-dots"
            case .capture: "viewfinder"
            case .output: "square.and.arrow.down"
            case .floating: "pin"
            case .shortcuts: "command"
            case .library: "square.stack"
            case .privacy: "lock.shield"
            }
        }

        var subtitle: String {
            switch self {
            case .general: "Startup options and your capture defaults."
            case .appearance: "Choose a look and arrange the controls you use."
            case .capture: "Choose what to capture and what happens next."
            case .output: "Set the format, name, and location of saved images."
            case .floating: "Set up your capture thumbnails and pinned images."
            case .shortcuts: "Assign keys to capture modes, actions, and editor tools."
            case .library: "Manage the captures stored on this Mac."
            case .privacy: "Manage screen access and how captures are processed."
            case .assistant: "Choose how Ask answers questions about a capture."
            }
        }
    }

    public init(store: SettingsStore, hasScreenAccess: Bool, initialSection: Section = .general,
                assistantService: @escaping (AssistantProvider) -> any AssistantService = Assistant.service(for:),
                openPrivacy: @escaping () -> Void) {
        self.store = store; self.hasScreenAccess = hasScreenAccess
        self.openPrivacy = openPrivacy
        self.assistantService = assistantService
        _section = LocalState(initialValue: initialSection)
    }

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
            ZStack {
                page.id(section)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: DS.sm)))
            }.animation(DS.Motion.panel(reduceMotion), value: section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(S.canvas(scheme))
        .tint(S.accent(scheme)).controlSize(.small)
        .ignoresSafeArea()
        .environment(\.settingsCompact, store.preferences.customization.density == .compact)
        .onChange(of: section) { previous, _ in visited.insert(previous) }
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled; needsLoginApproval = SMAppService.mainApp.status == .requiresApproval }
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: S.sectionGap) {
                header
                switch section {
                case .general: general
                case .appearance: AppearanceSettings(store: store)
                case .assistant: AssistantSettings(store: store, factory: assistantService)
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
        .environment(\.settingsFirstVisit, !visited.contains(section))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.xs) {
            Text(section.rawValue).font(S.title).accessibilityAddTraits(.isHeader)
            Text(section.subtitle).font(S.label).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var matchingSections: [Section] {
        guard !search.trimmingCharacters(in: .whitespaces).isEmpty else { return Section.allCases }
        return Section.allCases.filter { item in
            let keywords: String
            switch item {
            case .general: keywords = "login startup dock"
            case .appearance: keywords = "theme dark light system accent density compact glass solid chrome toolbar editor tools area overlay labels thumbnail buttons"
            case .assistant: keywords = "ask chatgpt codex claude provider model account sign in out privacy redact text conversations suggestions"
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
        GeometryReader { bounds in
            sidebarContent(short: bounds.size.height < S.shortWindowHeight)
        }.frame(width: S.sidebar)
    }

    private func sidebarContent(short: Bool) -> some View {
        VStack(alignment: .leading, spacing: DS.xs / 2) {
            if !short {
                HStack(spacing: DS.sm) {
                    BrandIcon(size: 20)
                    Text("SuperShot").font(DS.emphasis)
                }.padding(.horizontal, DS.sm).padding(.bottom, DS.md)
            }
            HStack(spacing: DS.xs) {
                Icon("magnifying-glass", size: DS.md).foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("Search settings", text: $search).textFieldStyle(.plain)
                    .focused($searchFocused).focusEffectDisabled()
                    .accessibilityLabel("Search settings")
                if !search.isEmpty {
                    Button { search = "" } label: { Icon("xmark.circle.fill") }
                        .buttonStyle(SettingsButtonStyle(kind: .plain)).accessibilityLabel("Clear search")
                }
            }
            .font(S.detail).padding(.horizontal, DS.sm).frame(height: S.controlHeight)
            .background(S.fill(scheme), in: RoundedRectangle(cornerRadius: S.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: S.controlRadius)
                .strokeBorder(searchFocused ? S.accent(scheme) : S.edge(scheme), lineWidth: searchFocused ? S.focusWidth : S.hairline))
            .padding(.bottom, DS.sm)
            ScrollView {
                VStack(alignment: .leading, spacing: short ? 0 : DS.xs) {
                    navigationGroup("Interface", [.general, .appearance], short: short)
                    navigationGroup("Capture & output", [.capture, .output, .floating, .shortcuts, .library], short: short)
                    navigationGroup("Account", [.privacy, .assistant], short: short)
                    if matchingSections.isEmpty {
                        Text("No matching settings").font(S.detail).foregroundStyle(.secondary).padding(DS.sm)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .id(reduceMotion ? matchingSections : nil).transition(.opacity)
            }
            .scrollIndicators(.hidden)
            .animation(DS.Motion.snappy(reduceMotion), value: matchingSections)
            Button { search = ""; section = .privacy } label: {
                HStack(spacing: DS.sm) {
                    Icon(hasScreenAccess ? "shield-check" : "shield-warning", size: DS.iconSize)
                    VStack(alignment: .leading, spacing: DS.xs) {
                        Text(hasScreenAccess ? "Screen access on" : "Screen access off").font(S.detail)
                        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.1")")
                            .font(S.mono).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }.padding(DS.sm)
            }
            .buttonStyle(SettingsButtonStyle(kind: .plain))
            .background(S.fill(scheme), in: RoundedRectangle(cornerRadius: S.radius))
            .overlay(RoundedRectangle(cornerRadius: S.radius).strokeBorder(S.edge(scheme), lineWidth: S.hairline))
        }
        .padding(DS.md).padding(.top, S.titlebarInset - DS.md)
        .frame(width: S.sidebar).frame(maxHeight: .infinity)
        .animation(DS.Motion.snappy(reduceMotion), value: section)
        .background(SettingsSurface(role: .sidebar))
        .overlay(alignment: .trailing) { Rectangle().fill(S.edge(scheme)).frame(width: S.hairline) }
        .onChange(of: search) { _, _ in
            if let first = matchingSections.first, !matchingSections.contains(section) { section = first }
        }
    }

    @ViewBuilder private func navigationGroup(_ title: String, _ pages: [Section], short: Bool) -> some View {
        let matches = pages.filter(matchingSections.contains)
        if !matches.isEmpty {
            Text(title.uppercased()).font(S.section).foregroundStyle(.secondary)
                .padding(.leading, DS.sm).padding(.top, short ? DS.xs : DS.sm).accessibilityAddTraits(.isHeader)
            ForEach(matches, id: \.self) { item in
                Button { section = item } label: {
                    HStack(spacing: DS.sm) {
                        SettingsIconTile(icon: item.icon, selected: section == item)
                        Text(highlighted(item.rawValue)).font(section == item ? S.navigation : S.label)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, DS.xs).frame(height: short ? S.controlHeight : S.navigationHeight)
                    .background {
                        if section == item {
                            let shape = RoundedRectangle(cornerRadius: S.controlRadius).fill(S.selection(scheme))
                            if reduceMotion { shape.transition(.opacity) }
                            else { shape.matchedGeometryEffect(id: "selection", in: navigation) }
                        }
                    }
                }
                .buttonStyle(SettingsButtonStyle(kind: .plain))
                .accessibilityAddTraits(section == item ? .isSelected : [])
                .transition(DS.Motion.rise(reduceMotion: reduceMotion))
            }
        }
    }

    private func highlighted(_ title: String) -> AttributedString {
        var result = AttributedString(title)
        if !search.isEmpty, let match = result.range(of: search, options: .caseInsensitive) {
            result[match].backgroundColor = S.selection(scheme)
            result[match].inlinePresentationIntent = .stronglyEmphasized
        }
        return result
    }

    // MARK: General

    private var general: some View {
        Group {
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
            group("Capture preferences", index: 1) {
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
            group("After capture", index: 1, footer: "Choose any combination. Auto-copy also applies to area captures and custom actions.") {
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
            group("What gets captured", index: 2) {
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
            group("Different actions for", index: 3, footer: "Override the defaults for a capture mode.") {
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
                Icon(selected ? "checkmark.square.fill" : "square")
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
            group("New pins", index: 1, footer: "Drag the image to move it. Drag an edge or corner to resize. Double-click to restore its initial size. Existing pins keep their own settings.") {
                PreferenceSlider("Initial size", value: $store.preferences.floating.pinSize, range: 240...1000, unit: "pt")
                separator
                PreferenceSlider("Opacity", value: $store.preferences.floating.pinOpacity, range: 0.2...1, percent: true)
                separator
                row("Show on every Space") { toggle("Show on every Space", $store.preferences.floating.pinAllSpaces) }
                separator
                row("Window shadow") { toggle("Pin window shadow", $store.preferences.floating.pinShadow) }
            }
            group("Click-through lock", index: 2, footer: "Locked pins let clicks reach the app behind them. Hover a locked pin to see how to unlock it, hold the unlock key over it, then click Unlock. Unlock All Pins in the SuperShot menu unlocks every pin at once.") {
                row("Lock a pin", "Hover a pin and choose the lock button") {
                    Icon("lock-simple", size: DS.iconSize).foregroundStyle(.secondary)
                }
                separator
                row("Unlock key", "Hold it while the pointer is over a locked pin") {
                    SettingsMenu(label: "Unlock key", options: PinUnlockKey.allCases.map { ($0, $0.title) },
                                 selection: $store.preferences.floating.pinUnlockKey)
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
            group("Image", index: 1) {
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
            group("File name", index: 2) {
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
            group("Location", index: 3) {
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
            group("Other", index: 1) { shortcutRows(Array(Shortcut.actions.dropFirst(9)) + presetActions) }
            group("Editor tools", index: 2, footer: "Single keys that switch tools while the editor is focused.") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.lg), count: 2), spacing: DS.sm) {
                    ForEach(Shortcut.editorDefaults.keys.sorted(), id: \.self) { id in editorKey(id) }
                }
            }
            group("Profiles", index: 3) {
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
                        Icon("xmark").font(S.detail).foregroundStyle(.secondary)
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
                             selection: $store.preferences.retentionDays).disabled(!store.preferences.historyEnabled)
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
            group("Local processing", index: 1) {
                row("On-device recognition", "Text and barcode recognition run on this Mac.") { EmptyView() }
                separator
                row("Ask about a capture", "Ask sends a capture to the provider you choose.") {
                    Button("Assistant…") { section = .assistant }.buttonStyle(SettingsButtonStyle())
                }
                separator
                row("Accessibility only on request", "Asked for only if you turn on automatic scrolling.") { EmptyView() }
            }
        }
    }

    // MARK: Building blocks

    private func group<Content: View>(_ title: String?, index: Int = 0, footer: String? = nil, @ViewBuilder content: @escaping () -> Content) -> some View {
        SettingsGroup(title: title, index: index, footer: footer, content: content)
    }
    private func row<Control: View>(_ title: String, _ detail: String? = nil, detailLines: Int? = nil,
                                    @ViewBuilder control: @escaping () -> Control) -> some View {
        SettingsRow(title, detail, detailLines: detailLines, control: control)
    }
    private var separator: some View { SettingsDivider() }
    private func toggle(_ label: String, _ binding: Binding<Bool>) -> some View {
        SettingsToggle(label: label, isOn: binding)
    }
    private func notice(_ message: String) -> some View {
        HStack(alignment: .top, spacing: DS.sm) {
            Icon("exclamationmark.triangle").accessibilityHidden(true)
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
