import SwiftUI
import AppKit
import DesignSystem
import Document
import Hotkeys
import AI
import Export
import ServiceManagement

private typealias S = DS.Preferences

public struct SettingsView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.settingsAccessibilityPreview) private var accessibilityPreview
    @Environment(\.settingsSidebarPreview) private var sidebarPreview
    @LocalState private var sidebarCollapsed = false
    @LocalState private var visited: Set<Section> = []
    @Bindable private var store: SettingsStore
    @LocalState private var section: Section
    @LocalState private var launchAtLogin = false
    @LocalState private var needsLoginApproval = false
    @LocalState private var launchError: String?
    @LocalState private var shortcutConflict: (id: String, message: String)?
    @LocalState private var previewThumbnailWidth: Double?
    @LocalState private var previewPinSize: Double?
    @LocalState private var previewPinOpacity: Double?
    @LocalState private var copiedPath: String?
    private let hasScreenAccess: Bool
    private let assistantService: (AssistantProvider) -> any AssistantService
    private let openLibrary: (() -> Void)?
    private let openRecordingSetup: (() -> Void)?
    private let openWebpageCapture: (() -> Void)?
    private let openReviewLinks: (() -> Void)?
    private let openPrivacy: () -> Void

    public enum Section: String, CaseIterable, Sendable {
        case general = "General", appearance = "Appearance", capture = "Capture", output = "Output", floating = "Pins & previews", shortcuts = "Shortcuts", library = "Library", privacy = "Privacy", assistant = "Assistant"
        var icon: String {
            switch self {
            case .general: "gear-six"
            case .appearance: "palette"
            case .assistant: "chat-circle-dots"
            case .capture: "frame-corners"
            case .output: "download-simple"
            case .floating: "push-pin"
            case .shortcuts: "command"
            case .library: "images"
            case .privacy: "shield-check"
            }
        }

        var subtitle: String {
            switch self {
            case .general: "Startup options and your capture defaults."
            case .appearance: "Choose a look and arrange the controls you use."
            case .capture: "Configure screenshots and open recording setup."
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
                openLibrary: (() -> Void)? = nil,
                openRecordingSetup: (() -> Void)? = nil,
                openWebpageCapture: (() -> Void)? = nil,
                openReviewLinks: (() -> Void)? = nil,
                openPrivacy: @escaping () -> Void) {
        self.store = store
        self.hasScreenAccess = hasScreenAccess
        self.assistantService = assistantService
        self.openLibrary = openLibrary
        self.openRecordingSetup = openRecordingSetup
        self.openWebpageCapture = openWebpageCapture
        self.openReviewLinks = openReviewLinks
        self.openPrivacy = openPrivacy
        _section = LocalState(initialValue: initialSection)
    }

    public var body: some View {
        GeometryReader { bounds in
            let sidebarWidth = bounds.size.width < S.compactWindowWidth ? S.compactSidebar : S.sidebar
            HStack(spacing: 0) {
                SettingsSidebar(section: $section, collapsed: $sidebarCollapsed,
                                short: bounds.size.height < S.shortWindowHeight,
                                hasScreenAccess: hasScreenAccess)
                    .frame(width: sidebarCollapsed ? S.iconSidebar : sidebarWidth)
                ZStack {
                    page.id(section)
                        .transition(.opacity)
                }
                .animation(DS.Motion.panel(reduceMotion), value: section)
                .background(S.canvas(scheme))
                .clipShape(.rect(cornerRadius: S.navigationRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: S.navigationRadius)
                        .strokeBorder(S.edge(scheme), lineWidth: S.hairline)
                        .allowsHitTesting(false)
                }
                .padding([.top, .bottom, .trailing], DS.xs)
            }
        }
        .background {
            SettingsRailSurface(solid: accessibilityPreview || reduceTransparency)
        }
        .tint(S.accent(scheme))
        .controlSize(.small)
        .ignoresSafeArea()
        .environment(\.settingsCompact, store.preferences.customization.density == .compact)
        .onChange(of: section) { previous, _ in visited.insert(previous) }
        .onAppear {
            if sidebarPreview.collapsed { sidebarCollapsed = true }
            refreshLoginStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLoginStatus()
        }
    }

    private func refreshLoginStatus() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled || status == .requiresApproval
        needsLoginApproval = status == .requiresApproval
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: S.sectionGap) {
                VStack(alignment: .leading, spacing: DS.xs) {
                    Text(section.rawValue).font(S.pageTitle).accessibilityAddTraits(.isHeader)
                    Text(section.subtitle).font(S.label).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, DS.sm)
                switch section {
                case .general: general
                case .appearance: AppearanceSettings(store: store)
                case .assistant:
                    AssistantSettings(store: store, factory: assistantService, openLibrarySettings: { section = .library })
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

    // MARK: General

    private var general: some View {
        Group {
            group("Startup") {
                row("Launch at login", "Start SuperShot when you sign in.") {
                    toggle("Launch at login", Binding(get: { launchAtLogin }, set: { enabled in
                        launchError = nil
                        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                        catch { launchError = error.localizedDescription }
                        refreshLoginStatus()
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
                if let launchError { notice(launchError).padding(.vertical, DS.xs) }
            }
            group("Capture preferences", index: 1) {
                row("Area capture", store.preferences.areaAction.title) {
                    pageLink(.capture)
                }
                separator
                row("Saved images", "\(ImageExport.formats.first { $0.id == store.preferences.fileFormat }?.name ?? "PNG") · \(abbreviated(store.preferences.saveFolder))") {
                    pageLink(.output)
                }
                separator
                row("Floating captures", "Thumbnails and pinned images") {
                    pageLink(.floating)
                }
            }
        }
    }

    // MARK: Capture

    private var capture: some View {
        Group {
            if openWebpageCapture != nil || openRecordingSetup != nil {
                group("Capture tools") {
                    if let openWebpageCapture {
                        row("Webpage capture", "Capture a viewport or full page from a URL.") {
                            Button("Capture webpage…", action: openWebpageCapture).buttonStyle(SettingsButtonStyle())
                        }
                    }
                    if let openRecordingSetup {
                        if openWebpageCapture != nil { separator }
                        row("Screen recording", "Choose a display, window, or area and set camera and audio inputs.") {
                            Button("Set up recording…", action: openRecordingSetup).buttonStyle(SettingsButtonStyle())
                        }
                    }
                }
            }
            group("Area selection") {
                row("Capture on mouse release", "Capture as soon as you release a new selection. When off, adjust the area before pressing Return.") {
                    toggle("Capture on mouse release", $store.preferences.captureOnRelease)
                }
            }
            group("After capture", index: 1) {
                VStack(alignment: .leading, spacing: DS.xs) {
                    Text("Default actions").font(S.navigation)
                    Text("Used by screen, window, scrolling, and webpage captures unless customized.")
                        .font(S.detail).foregroundStyle(.secondary)
                    actionChoices(store.preferences.afterCapture) { action in
                        if store.preferences.afterCapture.contains(action) { store.preferences.afterCapture.remove(action) }
                        else { store.preferences.afterCapture.insert(action) }
                    }
                }.padding(.vertical, DS.xs)
                separator
                row("Area capture", actionSummary(for: .area)) {
                    SettingsSegments([AfterCapture.editor, .thumbnail, .copy].map { ($0, $0.shortTitle) },
                                     selection: store.preferences.areaAction) { store.preferences.areaAction = $0 }
                        .frame(width: S.controlWidth)
                }
                separator
                row("Always copy", "Add Copy to every image capture, including area and custom actions.") {
                    toggle("Always copy", $store.preferences.autoCopyScreenshots)
                }
            }
            group("Per-mode actions", index: 2) {
                ForEach(Array([CaptureActionMode.screen, .window, .scrolling, .webpage].enumerated()), id: \.element) { index, mode in
                    if index > 0 { separator }
                    let id = mode.rawValue
                    let title = "\(id.capitalized) captures"
                    row(title, actionSummary(for: mode)) {
                        SettingsSegments([(false, "Defaults"), (true, "Custom")], selection: store.preferences.modeActions[id] != nil) { customized in
                            store.preferences.modeActions[id] = customized ? store.preferences.afterCapture : nil
                        }.frame(width: S.controlWidth)
                        .accessibilityLabel("Actions for \(title.lowercased())")
                    }
                    if let actions = store.preferences.modeActions[id] {
                        actionChoices(actions) { action in
                            if actions.contains(action) { store.preferences.modeActions[id]?.remove(action) }
                            else { store.preferences.modeActions[id]?.insert(action) }
                        }.padding(.bottom, DS.sm)
                            .transition(DS.Motion.rise(reduceMotion: reduceMotion))
                    }
                }
            }.animation(DS.Motion.panel(reduceMotion), value: store.preferences.modeActions)
            group("Capture options", index: 3) {
                row("Include the pointer") { toggle("Include the pointer", $store.preferences.includeCursor) }
                separator
                row("Keep window shadow", "Off trims the shadow from window captures.") { toggle("Keep window shadow", $store.preferences.keepWindowShadow) }
                separator
                row("Hide desktop icons") { toggle("Hide desktop icons", $store.preferences.hideDesktopIcons) }
                separator
                row("Capture sound") {
                    SettingsMenu(label: "Capture sound", options: [(nil as String?, "Off")] + Preferences.captureSoundNames.map { (Optional($0), $0) },
                                 selection: captureSound)
                }
                separator
                row("Apply my backdrop", "Uses the backdrop saved with “Use for new captures” in the editor.") {
                    toggle("Apply my backdrop", $store.preferences.automaticBackdrop)
                }
            }
            group("Selection appearance", index: 4) {
                row("Selection tint") {
                    SettingsMenu(label: "Selection tint", options: [(nil as DS.AccentChoice?, "App accent")] +
                                 DS.AccentChoice.allCases.map { (Optional($0), $0.title) }, selection: selectionTint)
                }
                separator
                PreferenceSlider("Tint opacity", value: Binding(get: { store.preferences.selectionTintOpacity ?? 0 }, set: {
                    store.preferences.selectionTintOpacity = $0
                }), range: 0...0.40, percent: true,
                    defaultLabel: store.preferences.selectionTintOpacity == nil ? "Default" : nil)
                if store.preferences.selectionTintOpacity != nil {
                    separator
                    row("Restore the standard area and window opacity") {
                        Button("Reset opacity") { store.preferences.selectionTintOpacity = nil }.buttonStyle(SettingsButtonStyle())
                    }
                }
            }
        }
    }
    private var captureSound: Binding<String?> {
        Binding(get: { store.preferences.captureSound ? store.preferences.captureSoundName ?? "Tink" : nil }, set: { name in
            var updated = store.preferences
            updated.captureSound = name != nil
            updated.captureSoundName = name
            store.preferences = updated
        })
    }
    private var selectionTint: Binding<DS.AccentChoice?> {
        Binding(get: {
            guard let tint = store.preferences.selectionTint else { return nil }
            return DS.AccentChoice.allCases.first { Self.selectionTintColor($0) == tint }
        }, set: { choice in store.preferences.selectionTint = choice.map(Self.selectionTintColor) })
    }
    static func selectionTintColor(_ choice: DS.AccentChoice) -> RGBA {
        let source = choice == .graphite ? NSColor.gray : DS.accentPalette(choice).base
        let color = source.usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        return RGBA(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent)
    }
    private func actionChoices(_ actions: Set<AfterCapture>, change: @escaping (AfterCapture) -> Void) -> some View {
        SettingsFlow(spacing: DS.xs) {
            ForEach(AfterCapture.allCases, id: \.self) { action in
                let selected = actions.contains(action)
                Button { change(action) } label: {
                    HStack(spacing: DS.xs) {
                        Icon(selected ? "checkmark.square.fill" : "square")
                            .foregroundStyle(selected ? Color.primary : Color.secondary).accessibilityHidden(true)
                        Text(action.shortTitle)
                    }.font(S.detail).padding(.horizontal, DS.sm)
                }
                .buttonStyle(SettingsButtonStyle(kind: .choice(selected)))
                .accessibilityLabel(action.title).accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
    private func actionSummary(for mode: CaptureActionMode) -> String {
        let effective = store.preferences.actions(for: mode)
        let actions = AfterCapture.allCases.filter(effective.contains).map(\.title)
        return actions.isEmpty ? "No follow-up actions" : actions.joined(separator: " · ")
    }

    // MARK: Floating captures

    private var floating: some View {
        Group {
            group("Quick-access thumbnail", footer: "Drag the preview into another app, or click it to open the editor.") {
                row("Screen corner") {
                    SettingsMenu(label: "Screen corner", options: ThumbnailCorner.allCases.map { ($0, $0.title) },
                                 selection: $store.preferences.floating.thumbnailCorner)
                }
                separator
                row("Dismiss after", "The timer pauses while you hover over the thumbnail.") {
                    SettingsMenu(label: "Dismiss after", options: [(0, "Keep until dismissed")] + [5, 10, 20, 30].map { ($0, "\($0) seconds") },
                                 selection: $store.preferences.floating.thumbnailSeconds)
                }
                separator
                PreferenceSlider("Thumbnail width", value: $store.preferences.floating.thumbnailWidth, range: 200...360, unit: "pt",
                                 onPreview: { previewThumbnailWidth = $0 })
                floatingPreview(alignment: thumbnailAlignment,
                                width: (previewThumbnailWidth ?? store.preferences.floating.thumbnailWidth) / S.previewThumbnailScale)
            }
            group("New pins", index: 1, footer: "Drag a pin between displays, drag an edge to resize it, or double-click to restore its size.") {
                PreferenceSlider("Initial size", value: $store.preferences.floating.pinSize, range: 240...1000, unit: "pt",
                                 onPreview: { previewPinSize = $0 })
                separator
                PreferenceSlider("Opacity", value: $store.preferences.floating.pinOpacity, range: 0.2...1, percent: true,
                                 onPreview: { previewPinOpacity = $0 })
                separator
                row("Show on every Space") { toggle("Show on every Space", $store.preferences.floating.pinAllSpaces) }
                separator
                row("Window shadow") { toggle("Pin window shadow", $store.preferences.floating.pinShadow) }
                floatingPreview(alignment: .center, width: (previewPinSize ?? store.preferences.floating.pinSize) / S.previewPinScale,
                                height: S.previewPinHeight, opacity: previewPinOpacity ?? store.preferences.floating.pinOpacity,
                                shadow: store.preferences.floating.pinShadow)
            }
            group("Click-through lock", index: 2, footer: "Use Unlock All Pins in the SuperShot menu to restore all pins at once.") {
                row("Unlock key", "Hover over a locked pin, hold this key, then click Unlock.") {
                    SettingsMenu(label: "Unlock key", options: PinUnlockKey.allCases.map { ($0, $0.title) },
                                 selection: $store.preferences.floating.pinUnlockKey)
                }
                separator
                row("Lock a pin", "Choose Lock pin here or press L on a focused pin to fix its position and pass clicks through.") { EmptyView() }
            }
        }
    }

    private var thumbnailAlignment: Alignment {
        switch store.preferences.floating.thumbnailCorner {
        case .topLeft: .topLeading
        case .topRight: .topTrailing
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        }
    }

    private func floatingPreview(alignment: Alignment, width: CGFloat, height: CGFloat = S.previewHeight,
                                 opacity: Double = 1, shadow: Bool = false) -> some View {
        ZStack(alignment: alignment) {
            RoundedRectangle(cornerRadius: S.controlRadius).fill(S.fill(scheme))
            VStack(alignment: .leading, spacing: DS.xs) {
                RoundedRectangle(cornerRadius: DS.xs / 2).fill(S.edge(scheme)).frame(width: DS.xxl, height: DS.xs)
                RoundedRectangle(cornerRadius: DS.xs / 2).fill(S.edge(scheme)).frame(width: DS.xl, height: DS.xs)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            RoundedRectangle(cornerRadius: S.controlRadius)
                .fill(S.raised(scheme))
                .overlay(RoundedRectangle(cornerRadius: S.controlRadius).strokeBorder(S.controlEdge(scheme), lineWidth: S.hairline))
                .overlay(Icon("image", size: DS.lg).foregroundStyle(.secondary))
                .frame(width: width, height: width / S.previewAspectRatio)
                .shadow(color: shadow ? .black.opacity(DS.subtleOpacity) : .clear, radius: DS.xs, y: DS.stroke)
                .opacity(opacity)
                .padding(DS.sm)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    // MARK: Output

    private var output: some View {
        Group {
            group("Formats") {
                row("File format") {
                    SettingsMenu(label: "File format", options: ImageExport.formats.map { ($0.id, $0.name) }, selection: $store.preferences.fileFormat)
                }
                separator
                row("Clipboard format") {
                    SettingsMenu(label: "Clipboard format", options: ImageExport.formats.filter { $0.id != "com.adobe.pdf" }.map { ($0.id, $0.name) },
                                 selection: $store.preferences.clipboardFormat)
                }
                if let qualityLabel {
                    separator
                    PreferenceSlider(qualityLabel, value: $store.preferences.quality, range: 0.1...1, percent: true)
                }
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
                SettingsFlow(spacing: DS.xs) {
                    ForEach(["{date}", "{time}", "{app}", "{window}", "{counter}", "{size}"], id: \.self) { token in
                        Button { store.preferences.filenameTemplate += (store.preferences.filenameTemplate.isEmpty ? "" : " ") + token } label: {
                            Text(token).font(S.mono)
                        }.buttonStyle(SettingsButtonStyle()).help("Add \(token)").accessibilityLabel("Insert \(token) token")
                    }
                }.padding(.top, DS.sm)
                VStack(alignment: .leading, spacing: DS.xs) {
                    Text("Example filename").font(S.detail).foregroundStyle(.secondary)
                    Text(exampleName).font(S.mono).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, DS.md)
            }
            group("Location", index: 3) {
                saveFolder
                separator
                row("Subfolders") {
                    SettingsSegments([("none", "None"), ("date", "By date"), ("app", "By app")],
                                    selection: store.preferences.subfolders) { store.preferences.subfolders = $0 }.frame(width: S.controlWidth)
                }
                separator
                row("Keep exported files updated", "Update a linked auto-saved image when you edit its capture in the Library.") {
                    toggle("Keep exported files updated", $store.preferences.keepExportUpdated)
                        .disabled(!store.preferences.historyEnabled)
                }
            }
        }
    }
    private var qualityLabel: String? {
        Self.qualityLabel(fileFormat: store.preferences.fileFormat, clipboardFormat: store.preferences.clipboardFormat)
    }

    static func qualityLabel(fileFormat: String, clipboardFormat: String) -> String? {
        let adjustable = ["public.jpeg", "public.heic", "org.webmproject.webp", "public.avif"]
        return switch (adjustable.contains(fileFormat), adjustable.contains(clipboardFormat)) {
        case (true, true): "File and clipboard quality"
        case (true, false): "File quality"
        case (false, true): "Clipboard quality"
        case (false, false): nil
        }
    }

    private var saveFolder: some View {
        let path = store.preferences.saveFolder
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        let canReveal = exists && isDirectory.boolValue
        return VStack(alignment: .leading, spacing: DS.sm) {
            row("Save folder") {
                Button("Choose…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.canCreateDirectories = true
                    if canReveal { panel.directoryURL = folder }
                    if panel.runModal() == .OK, let url = panel.url { store.preferences.saveFolder = url.path }
                }.buttonStyle(SettingsButtonStyle())
            }
            Text(abbreviated(path)).font(S.mono).foregroundStyle(.secondary)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true).help(path)
                .accessibilityLabel(path)
            SettingsFlow(spacing: DS.sm) {
                Button(copiedPath == path ? "Copied" : "Copy path") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    copiedPath = pasteboard.setString(path, forType: .string) ? path : nil
                }.buttonStyle(SettingsButtonStyle())
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                    .buttonStyle(SettingsButtonStyle()).disabled(!canReveal)
                    .help(canReveal ? "Show the save folder in Finder" : "A save folder is required")
            }
            if exists && !canReveal {
                notice("This location is a file. Choose a folder for new exports.")
            }
        }.padding(.bottom, DS.sm)
    }
    private var exampleName: String {
        let format = ImageExport.formats.first { $0.id == store.preferences.fileFormat }
        return ImageExport.templateFilename(store.preferences.filenameTemplate, date: Date(), app: "Safari", window: "Apple", counter: store.preferences.filenameCounter,
                                            width: 1440, height: 900, extensionName: format?.extensionName ?? "png")
    }
    private func abbreviated(_ path: String) -> String { (path as NSString).abbreviatingWithTildeInPath }

    // MARK: Shortcuts

    private var shortcuts: some View {
        let managementIDs = Set(["last", "recent", "history", "pin", "icons", "unlockPin"])
        let captureActions = Shortcut.actions.filter { !managementIDs.contains($0.id) }
        let managementActions = Shortcut.actions.filter { managementIDs.contains($0.id) }
        let presetActions = store.preferences.backdropPresets.map { (id: "preset." + $0.id.uuidString, title: "Backdrop: " + $0.name) }
        return Group {
            if let error = store.shortcutError { notice(error) }
            group("Capture", footer: "Click a shortcut, then press the new keys. Include ⌘, ⌃, or ⌥. Esc cancels.") {
                shortcutRows(captureActions)
            }
            group("Open and manage", index: 1) { shortcutRows(managementActions + presetActions) }
            group("Editor tools", index: 2, footer: "Single keys that switch tools while the editor is focused.") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: S.shortcutColumnWidth), spacing: DS.lg)], alignment: .leading, spacing: DS.sm) {
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
                clearShortcutConflict()
                var updated = store.preferences
                updated.shortcuts = Shortcut.defaults
                updated.toolShortcuts = [:]
                store.preferences = updated
            }.buttonStyle(SettingsButtonStyle())
        }
    }
    @ViewBuilder private func shortcutRows(_ actions: [(id: String, title: String)]) -> some View {
        ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
            if index > 0 { separator }
            row(action.title, shortcutMessage(for: action.id)) {
                HStack(spacing: DS.xs) {
                    ShortcutRecorder(neutral: true, shortcut: store.preferences.shortcuts[action.id] ?? Shortcut.unassigned,
                                     recordingChanged: { store.isRecordingShortcut = $0 }) { shortcut in assign(shortcut, to: action.id) }
                        .frame(width: S.shortcutRecorderWidth, height: S.controlHeight).accessibilityLabel("\(action.title) shortcut")
                    if store.preferences.shortcuts[action.id] != nil {
                        Button {
                            clearShortcutConflict()
                            store.preferences.shortcuts[action.id] = nil
                        } label: {
                            Icon("x", size: DS.md).foregroundStyle(.secondary)
                                .frame(width: S.shortcutRemoveWidth, height: S.controlHeight)
                        }
                        .buttonStyle(SettingsButtonStyle(kind: .plain)).help("Remove shortcut")
                        .accessibilityLabel("Remove \(action.title) shortcut")
                    } else {
                        Color.clear.frame(width: S.shortcutRemoveWidth, height: S.controlHeight)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }
    private func assign(_ shortcut: Shortcut, to id: String) {
        var proposed = store.preferences.shortcuts
        proposed[id] = shortcut
        if Shortcut.hasConflict(Array(proposed.values)) {
            let current = proposed.first { $0.key != id && $0.value.keyCode == shortcut.keyCode && $0.value.modifiers == shortcut.modifiers }
            let title = Shortcut.actions.first { $0.id == current?.key }?.title
            let preset = store.preferences.backdropPresets.first { "preset." + $0.id.uuidString == current?.key }?.name
            shortcutConflict = (id, "\(shortcut.display) is assigned to \(title ?? preset ?? "another action").")
            return
        }
        clearShortcutConflict()
        store.preferences.shortcuts = proposed
    }
    private func editorKey(_ id: String) -> some View {
        VStack(alignment: .leading, spacing: DS.xs) {
            HStack {
                Text(editorToolTitle(id)).font(S.label)
                Spacer()
                TextField("Key", text: Binding(
                    get: { (store.preferences.toolShortcuts[id] ?? Shortcut.editorDefaults[id] ?? "").uppercased() },
                    set: { assignEditorKey($0, to: id) }
                ))
                .multilineTextAlignment(.center).modifier(SettingsField()).frame(width: DS.xl + DS.sm)
                .accessibilityLabel("\(editorToolTitle(id)) tool key")
            }
            if let message = shortcutMessage(for: "editor.\(id)") { notice(message) }
        }
    }
    private func assignEditorKey(_ value: String, to id: String) {
        guard let key = value.lowercased().last, key.isLetter || key.isNumber else { return }
        let effective = Shortcut.editorDefaults.merging(store.preferences.toolShortcuts) { _, new in new }
        if let other = effective.first(where: { $0.key != id && $0.value == String(key) })?.key {
            shortcutConflict = ("editor.\(id)", "\(String(key).uppercased()) is assigned to \(editorToolTitle(other)).")
            return
        }
        clearShortcutConflict()
        store.preferences.toolShortcuts[id] = String(key)
    }
    private func editorToolTitle(_ id: String) -> String { id == "picker" ? "Color picker" : id.capitalized }
    private func shortcutMessage(for id: String) -> String? {
        guard shortcutConflict?.id == id else { return nil }
        return shortcutConflict?.message
    }
    private func clearShortcutConflict() {
        shortcutConflict = nil
        store.shortcutError = nil
    }
    private func useSystemKeys() {
        let alert = NSAlert()
        alert.messageText = "Use ⌘⇧3, ⌘⇧4, and ⌘⇧5"
        alert.informativeText = "First turn off the macOS screenshot shortcuts in System Settings → Keyboard → Keyboard Shortcuts → Screenshots. SuperShot cannot take over keys while macOS still uses them."
        alert.addButton(withTitle: "Open Keyboard Settings"); alert.addButton(withTitle: "Assign keys"); alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn, let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") { NSWorkspace.shared.open(url) }
        if response == .alertSecondButtonReturn {
            clearShortcutConflict()
            guard let updated = Self.shortcutsApplyingSystemScreenshotPreset(to: store.preferences.shortcuts) else {
                store.shortcutError = "⌘⇧3, ⌘⇧4, or ⌘⇧5 is already assigned in SuperShot. Free those keys and try again."
                return
            }
            store.preferences.shortcuts = updated
        }
    }

    static func shortcutsApplyingSystemScreenshotPreset(to shortcuts: [String: Shortcut]) -> [String: Shortcut]? {
        let merged = shortcuts.merging(Shortcut.systemScreenshotPreset) { _, preset in preset }
        return Shortcut.hasConflict(Array(merged.values)) ? nil : merged
    }

    private func importShortcuts() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let profile = try JSONDecoder().decode(ShortcutProfile.self, from: Data(contentsOf: url))
            try profile.validate()
            clearShortcutConflict()
            var updated = store.preferences
            updated.shortcuts = profile.global
            updated.toolShortcuts = profile.editor.mapValues { $0.lowercased() }
            store.preferences = updated
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
        group("Capture history") {
            if let openLibrary {
                row("Capture library", "Browse, search, and reopen editable captures.") {
                    Button("Open Library", action: openLibrary).buttonStyle(SettingsButtonStyle())
                }
                separator
            }
            row("Keep capture history", "Save new captures in the Library on this Mac.") {
                toggle("Keep capture history", $store.preferences.historyEnabled)
            }
            separator
            row("Keep captures for", retentionDetail) {
                SettingsMenu(label: "History retention", options: [(7, "7 days"), (30, "30 days"), (90, "90 days"), (0, "Forever")],
                             selection: $store.preferences.retentionDays).disabled(!store.preferences.historyEnabled)
            }
            separator
            row("Organize new captures locally", "Suggest titles, tags, and summaries with on-device recognition and Apple Intelligence where available.") {
                toggle("Organize new captures locally", $store.preferences.organizeCapturesLocally)
                    .disabled(!store.preferences.historyEnabled)
            }
            if store.preferences.historyEnabled && store.preferences.organizeCapturesLocally {
                separator
                row("Organization model", "Use Vision when Apple Intelligence is unavailable.") {
                    SettingsMenu(label: "Organization model",
                                 options: [(true, "Apple Intelligence + Vision"), (false, "Vision + text recognition")],
                                 selection: $store.preferences.useAppleIntelligenceForOrganization)
                }.transition(DS.Motion.rise(reduceMotion: reduceMotion))
            }
        }
        .animation(DS.Motion.panel(reduceMotion), value: store.preferences.organizeCapturesLocally)
    }
    private var retentionDetail: String {
        if !store.preferences.historyEnabled { return "Existing captures remain available while history is off." }
        if store.preferences.retentionDays == 0 { return "Keep Library captures until you delete them." }
        return "Saving a new capture removes Library entries older than \(store.preferences.retentionDays) days. Exports are kept."
    }

    private var privacy: some View {
        Group {
            group("Permissions") {
                row(hasScreenAccess ? "Screen access allowed" : "Screen access needed",
                    hasScreenAccess ? "Required for screenshots and screen recordings." : "Allow SuperShot in Privacy & Security → Screen & System Audio Recording.") {
                    Button("Open System Settings", action: openPrivacy).buttonStyle(SettingsButtonStyle())
                }
                separator
                row("Accessibility", "SuperShot requests this permission when you enable automatic scrolling.") { EmptyView() }
                separator
                row("Camera and microphone", "Permission is requested for enabled inputs when you start recording.") { EmptyView() }
            }
            group("Capture data", index: 1) {
                row("Processed on this Mac", "Recognize text and barcodes, edit screenshots, and search your Library locally.") { EmptyView() }
                separator
                row("Sent when you use Ask", "Your selected provider receives the screenshot or recording frame when you send a question.") {
                    pageLink(.assistant)
                }
                separator
                row("Shared when you create a review link", "The rendered capture or recording is uploaded to the destination you choose.") {
                    if let openReviewLinks {
                        Button("Review Links…", action: openReviewLinks).buttonStyle(SettingsButtonStyle())
                    }
                }
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
    private func pageLink(_ destination: Section) -> some View {
        Button { section = destination } label: {
            HStack(spacing: DS.xs) {
                Text(destination.rawValue)
                Icon("caret-right", size: DS.md).accessibilityHidden(true)
            }
        }.buttonStyle(SettingsButtonStyle()).accessibilityLabel("Open \(destination.rawValue) settings")
    }
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
