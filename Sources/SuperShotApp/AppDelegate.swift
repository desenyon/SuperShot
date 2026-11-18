import AppKit
import SwiftUI
import DesignSystem
import Settings
import Capture
import Hotkeys
import Carbon

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SettingsStore()
    let permission = ScreenPermission()
    private let hotkeys = GlobalHotkeys()
    private var hotkeysSuspended = false
    private var registeredShortcuts: [String: Shortcut] = [:]
    /// The shortcuts currently shown in the menus, so menus are rebuilt only when they change.
    private var menuShortcuts: [String: Shortcut]?
    private var appliedAppearance: AppAppearance?
    private var appliedDockIcon: Bool?
    private lazy var captures = CaptureController(settings: settings, permission: permission, requestPermission: { [weak self] in self?.showSettings() })
    private var appliedKeepConversations: Bool?
    private var statusItem: NSStatusItem?
    private var welcomeWindow: NSWindow?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyPreferences()
        observePreferences()
        captures.prepare()
        if settings.claimFirstLaunchSetup(screenAccess: permission.state == .authorized) {
            showWelcome()
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag && !captures.hasVisibleSurface { showSettings() }; return true
    }
    func applicationDidBecomeActive(_ notification: Notification) { permission.refresh() }

    private func observePreferences() {
        withObservationTracking {
            _ = settings.preferences
            _ = settings.isRecordingShortcut
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyPreferences()
                self?.observePreferences()
            }
        }
    }
    private func applyPreferences() {
        // Preferences change on every slider tick, so only touch the app when a value that matters here actually changed.
        let preferences = settings.preferences
        captures.updateAssistantPreferences()
        if appliedAppearance != preferences.appearance {
            appliedAppearance = preferences.appearance
            switch preferences.appearance {
            case .system: NSApp.appearance = nil
            case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
            case .light: NSApp.appearance = NSAppearance(named: .aqua)
            }
        }
        if appliedKeepConversations == true && !preferences.assistant.keepConversations { captures.forgetConversations() }
        appliedKeepConversations = preferences.assistant.keepConversations
        if captures.pins.unlockKey != preferences.floating.pinUnlockKey { captures.pins.unlockKey = preferences.floating.pinUnlockKey }
        let theme = ThemeState.shared, look = preferences.customization
        // Assigning an @Observable property invalidates its readers even when unchanged; guard so slider ticks stay free.
        if theme.accent != look.accent { theme.accent = look.accent }
        if theme.density != look.density { theme.density = look.density }
        if theme.chrome != look.chrome { theme.chrome = look.chrome }
        if appliedDockIcon != preferences.showDockIcon {
            appliedDockIcon = preferences.showDockIcon
            NSApp.setActivationPolicy(preferences.showDockIcon ? .regular : .accessory)
        }
        if menuShortcuts != settings.preferences.shortcuts { menuShortcuts = settings.preferences.shortcuts; configureMenu() }
        configureHotkeys()
    }

    /// Capture commands shared by the menu bar item and the main menu. `id` matches the shortcut action id.
    private var captureCommands: [[(id: String, title: String, symbol: String, action: Selector)]] {
        [
            [("area", "Capture Area", "rectangle.dashed", #selector(captureArea)),
             ("window", "Capture Window", "macwindow", #selector(captureWindow)),
             ("screen", "Capture Screen", "display", #selector(captureScreen)),
             ("all", "Capture All Displays", "rectangle.on.rectangle", #selector(captureAll)),
             ("scrolling", "Scrolling Capture", "arrow.up.and.down.text.horizontal", #selector(captureScrolling)),
             ("previous", "Capture Previous Area", "arrow.counterclockwise", #selector(capturePrevious))],
            [("text", "Copy Text from Area", "text.viewfinder", #selector(captureText)),
             ("code", "Scan QR or Barcode", "qrcode.viewfinder", #selector(captureCode))],
            [("last", "Open Last Capture", "pencil.tip.crop.circle", #selector(openLastCapture)),
             ("history", "Library", "photo.stack", #selector(showHistory)),
             ("", "Open Image or Project…", "folder", #selector(openImage)),
             ("", "Open from Clipboard", "doc.on.clipboard", #selector(openClipboard)),
             ("pin", "Pin from Clipboard", "pin", #selector(pinClipboard)),
             ("", "Unlock All Pins", "lock.open", #selector(unlockPins))]
        ]
    }
    private func addCaptureCommands(to menu: NSMenu) {
        for (index, group) in captureCommands.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            for command in group {
                let item = add(command.title, action: command.action, symbol: command.symbol, to: menu)
                // Shown for reference; the global hotkey does the work, so these never need the app to be frontmost.
                if let shortcut = settings.preferences.shortcuts[command.id], !shortcut.keyLabel.isEmpty {
                    item.keyEquivalent = shortcut.keyLabel.lowercased()
                    var mask: NSEvent.ModifierFlags = []
                    if shortcut.modifiers & UInt32(cmdKey) != 0 { mask.insert(.command) }
                    if shortcut.modifiers & UInt32(shiftKey) != 0 { mask.insert(.shift) }
                    if shortcut.modifiers & UInt32(optionKey) != 0 { mask.insert(.option) }
                    if shortcut.modifiers & UInt32(controlKey) != 0 { mask.insert(.control) }
                    item.keyEquivalentModifierMask = mask
                }
                if command.id == "area" {
                    let timed = NSMenuItem(title: "Capture Area After Delay", action: nil, keyEquivalent: "")
                    timed.image = Icons.image("timer", size: 16)
                    let submenu = NSMenu()
                    for seconds in [3, 5, 10] {
                        let item = NSMenuItem(title: "\(seconds) seconds", action: #selector(timedCapture(_:)), keyEquivalent: "")
                        item.tag = seconds; item.target = self; submenu.addItem(item)
                    }
                    timed.submenu = submenu; menu.addItem(timed)
                }
            }
        }
    }
    private func configureMenu() {
        let main = NSMenu()
        let appMenu = NSMenu()
        let item = NSMenuItem()
        item.submenu = appMenu; main.addItem(item)
        add("About SuperShot", action: #selector(about), to: appMenu)
        appMenu.addItem(.separator())
        add("Settings…", action: #selector(showSettings), key: ",", to: appMenu)
        appMenu.addItem(.separator())
        add("Quit SuperShot", action: #selector(quit), key: "q", to: appMenu)
        // Keep native text fields' editing shortcuts in the responder chain.
        // Canvas-specific equivalents continue to be handled by CanvasView.
        let editMenu = NSMenu(title: "Edit")
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = editMenu; main.addItem(editItem)
        for (title, selector, key) in [("Undo", "undo:", "z"), ("Redo", "redo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            if title == "Cut" { editMenu.addItem(.separator()) }
            let command = NSMenuItem(title: title, action: Selector(selector), keyEquivalent: key)
            if title == "Redo" { command.keyEquivalentModifierMask = [.command, .shift] }
            editMenu.addItem(command)
        }
        let captureMenu = NSMenu(title: "Capture")
        let captureItem = NSMenuItem(title: "Capture", action: nil, keyEquivalent: "")
        captureItem.submenu = captureMenu; main.addItem(captureItem)
        addCaptureCommands(to: captureMenu)
        let windowMenu = NSMenu(title: "Window")
        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        windowItem.submenu = windowMenu; main.addItem(windowItem)
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        NSApp.mainMenu = main

        if statusItem == nil {
            let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            status.button?.image = Brand.menuBarImage()
            status.button?.toolTip = "SuperShot"
            statusItem = status
        }
        let menu = NSMenu()
        addCaptureCommands(to: menu)
        menu.addItem(.separator())
        add("Settings…", action: #selector(showSettings), key: ",", symbol: "gearshape", to: menu)
        menu.addItem(.separator())
        add("Quit SuperShot", action: #selector(quit), key: "q", to: menu)
        statusItem?.menu = menu
    }
    @discardableResult private func add(_ title: String, action: Selector, key: String = "", symbol: String? = nil, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        if let symbol { item.image = Icons.image(symbol, size: 16) }
        menu.addItem(item)
        return item
    }
    @objc func showWelcome() {
        if welcomeWindow == nil {
            let view = WelcomeView(settings: settings, permission: permission, capture: { [weak self] in self?.startCapture($0) },
                                   openSettings: { [weak self] in self?.showSettings() }, openPrivacy: { [weak self] in self?.openPrivacy() }, finish: { [weak self] in
                self?.settings.preferences.onboardingCompleted = true
                self?.welcomeWindow?.close()
            })
            welcomeWindow = makeWindow(title: "SuperShot Setup", size: DS.welcomeSize, view: view)
        }
        present(welcomeWindow)
    }
    @objc func showSettings() {
        if settingsWindow == nil {
            let view = SettingsContainer(store: settings, permission: permission, openPrivacy: { [weak self] in self?.openPrivacy() })
            settingsWindow = makeWindow(title: "SuperShot Settings", size: DS.settingsSize, view: view, resizable: true)
            settingsWindow?.isOpaque = false
            settingsWindow?.backgroundColor = .clear
        }
        present(settingsWindow)
    }
    private func startCapture(_ id: String) {
        switch id {
        case "screen": captureScreen()
        case "window": captureWindow()
        case "scrolling": captureScrolling()
        case "text": captureText()
        case "code": captureCode()
        default: captureArea()
        }
    }
    func openPrivacy() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }
    private func makeWindow<V: View>(title: String, size: CGSize, view: V, resizable: Bool = false) -> NSWindow {
        let fitted = DS.fittingWindowSize(preferred: size, available: NSScreen.main?.visibleFrame.size ?? size)
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        if resizable { style.insert(.resizable) }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: fitted), styleMask: style, backing: .buffered, defer: false)
        window.title = title
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        // Dragging the background would fight with sliders and other drag controls in the content.
        window.isMovableByWindowBackground = false
        if resizable { window.minSize = CGSize(width: min(fitted.width, 680), height: min(fitted.height, 440)) }
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: fitted)
        window.contentView = hosting
        window.setContentSize(fitted)
        window.center()
        return window
    }
    private func present(_ window: NSWindow?) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    @objc private func about() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "SuperShot", .credits: NSAttributedString(string: "Capture, annotate, and share. Everything stays on your Mac.")])
        NSApp.activate(ignoringOtherApps: true)
    }
    private func hideMainWindows() {
        welcomeWindow?.orderOut(nil); settingsWindow?.orderOut(nil)
    }
    private func configureHotkeys() {
        if settings.isRecordingShortcut {
            hotkeys.unregisterAll(); hotkeysSuspended = true; return
        }
        let resume = hotkeysSuspended
        hotkeysSuspended = false
        guard resume || registeredShortcuts != settings.preferences.shortcuts else { return }
        hotkeys.unregisterAll()
        var actions: [(String, () -> Void)] = [
            ("screen", { [weak self] in self?.captureScreen() }),
            ("area", { [weak self] in self?.captureArea() }),
            ("window", { [weak self] in self?.captureWindow() }),
            ("all", { [weak self] in self?.captureAll() }),
            ("previous", { [weak self] in self?.capturePrevious() }),
            ("scrolling", { [weak self] in self?.captureScrolling() }),
            ("text", { [weak self] in self?.captureText() }),
            ("code", { [weak self] in self?.captureCode() }),
            ("timed", { [weak self] in self?.captures.captureTimed(seconds:3) }),
            ("last", { [weak self] in self?.openLastCapture() }),
            ("history", { [weak self] in self?.showHistory() }),
            ("pin", { [weak self] in self?.captures.pinClipboard() }),
            ("icons", { [weak self] in self?.settings.preferences.hideDesktopIcons.toggle() })
        ]
        for preset in settings.preferences.backdropPresets {actions.append(("preset."+preset.id.uuidString,{ [weak self] in self?.captures.applyPreset(preset.backdrop) }))}
        do {
            for (index, pair) in actions.enumerated() {
                if let shortcut = settings.preferences.shortcuts[pair.0] {
                    try hotkeys.register(id: UInt32(index + 1), shortcut: shortcut, action: pair.1)
                }
            }
            registeredShortcuts = settings.preferences.shortcuts
        } catch {
            hotkeys.unregisterAll()
            settings.shortcutError = error.localizedDescription
            // Restore the last working registrations, keeping the rejected assignment out of storage.
            let previous = registeredShortcuts
            for (index, pair) in actions.enumerated() {
                if let shortcut = previous[pair.0] {
                    try? hotkeys.register(id: UInt32(index + 1), shortcut: shortcut, action: pair.1)
                }
            }
            if !previous.isEmpty { settings.preferences.shortcuts = previous }
        }
    }
    @objc private func captureScreen() { hideMainWindows(); captures.capture(.screen) }
    @objc private func captureArea() { hideMainWindows(); captures.capture(.area) }
    @objc private func captureWindow() { hideMainWindows(); captures.capture(.window) }
    @objc private func capturePrevious() { captures.capture(.previous) }
    @objc private func captureAll() { hideMainWindows(); captures.captureAllDisplays() }
    @objc private func timedCapture(_ sender:NSMenuItem) { hideMainWindows(); captures.captureTimed(seconds:sender.tag) }
    @objc private func captureScrolling() { hideMainWindows(); captures.capture(.scrolling) }
    @objc private func captureText() { hideMainWindows(); captures.capture(.text) }
    @objc private func captureCode() { hideMainWindows(); captures.capture(.code) }
    @objc private func showHistory() { captures.showHistory() }
    @objc private func openImage() { captures.openImage() }
    @objc private func openClipboard() { captures.openClipboard() }
    @objc private func unlockPins() { captures.pins.unlockAll() }
    @objc private func pinClipboard() { captures.pinClipboard() }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        filenames.forEach { captures.openFile(URL(fileURLWithPath: $0)) }
        sender.reply(toOpenOrPrint: .success)
    }
    @objc private func openLastCapture() { captures.openLast() }
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {if url.isFileURL {captures.openFile(url)} else {handleURL(url)}}
    }
    func handleURL(_ url: URL) {
        guard url.scheme?.lowercased() == "supershot",let components=URLComponents(url:url,resolvingAgainstBaseURL:false) else{return}
        let query=Dictionary(components.queryItems?.map{($0.name,$0.value ?? "")} ?? [],uniquingKeysWith:{_,new in new})
        if url.host == "history" {captures.showHistory();return}
        guard url.host == "capture" else{return}
        hideMainWindows()
        if let delay=Int(query["delay"] ?? ""),[3,5,10].contains(delay) {captures.captureTimed(seconds:delay);return}
        switch query["mode"] ?? "area" {
        case "screen":captures.capture(.screen)
        case "window":captures.capture(.window)
        case "previous":captures.capture(.previous)
        case "text":captures.capture(.text)
        case "code":captures.capture(.code)
        case "scrolling":captures.capture(.scrolling)
        case "all":captures.captureAllDisplays()
        case "area":captures.capture(.area)
        default:break
        }
    }
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
        Task {await captures.flushEdits();sender.reply(toApplicationShouldTerminate:true)}
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) { hotkeys.unregisterAll() }
    @objc private func quit() { NSApp.terminate(nil) }
}

private struct SettingsContainer: View {
    let store: SettingsStore
    let permission: ScreenPermission
    let openPrivacy: () -> Void
    var body: some View {
        SettingsView(store: store, hasScreenAccess: permission.state == .authorized, openPrivacy: openPrivacy)
            .task {
                while !Task.isCancelled {
                    permission.refresh()
                    try? await Task.sleep(for: .seconds(2))
                }
            }
    }
}
