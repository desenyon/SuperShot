import Foundation
import Observation
import Hotkeys
import Document
import DesignSystem
import AI

public enum AppAppearance: String, Codable, CaseIterable, Sendable {
    case system, light, dark
    public var title: String { rawValue.capitalized }
}

public enum AfterCapture: String, Codable, CaseIterable, Sendable {
    case thumbnail, copy, save, editor, pin
    public var title: String {
        switch self { case .thumbnail: "Show thumbnail"; case .copy: "Copy to clipboard"; case .save: "Save to folder"; case .editor: "Open editor"; case .pin: "Pin to screen" }
    }
}

public enum CaptureActionMode: String, CaseIterable, Sendable {
    case screen, window, area, scrolling, webpage
}

public enum ThumbnailCorner: String, Codable, CaseIterable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight
    public var title: String {
        switch self { case .topLeft: "Top left"; case .topRight: "Top right"; case .bottomLeft: "Bottom left"; case .bottomRight: "Bottom right" }
    }
    public var isRight: Bool { self == .topRight || self == .bottomRight }
    public var isTop: Bool { self == .topLeft || self == .topRight }
}

/// The key that makes a locked pin clickable while held over it.
public enum PinUnlockKey: String, Codable, CaseIterable, Sendable {
    case option, command, control, shift
    public var symbol: String { switch self { case .option: "⌥"; case .command: "⌘"; case .control: "⌃"; case .shift: "⇧" } }
    public var title: String { "\(symbol) \(rawValue.capitalized)" }
}

public struct FloatingPreferences: Codable, Equatable, Sendable {
    public var thumbnailCorner: ThumbnailCorner = .bottomRight
    public var thumbnailSeconds: Int = 0
    public var thumbnailWidth: Double = 264
    public var pinSize: Double = 520
    public var pinOpacity: Double = 1
    public var pinAllSpaces = true
    public var pinShadow = true
    public var pinUnlockKey: PinUnlockKey = .option
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case thumbnailCorner, thumbnailSeconds, thumbnailWidth, pinSize, pinOpacity, pinAllSpaces, pinShadow, pinUnlockKey
    }
    // Every field decodes optionally so preferences saved by older versions keep their values.
    public init(from decoder: Decoder) throws {
        self.init()
        let v = try decoder.container(keyedBy: CodingKeys.self)
        thumbnailCorner = try v.decodeIfPresent(ThumbnailCorner.self, forKey: .thumbnailCorner) ?? thumbnailCorner
        thumbnailSeconds = try v.decodeIfPresent(Int.self, forKey: .thumbnailSeconds) ?? thumbnailSeconds
        thumbnailWidth = try v.decodeIfPresent(Double.self, forKey: .thumbnailWidth) ?? thumbnailWidth
        pinSize = try v.decodeIfPresent(Double.self, forKey: .pinSize) ?? pinSize
        pinOpacity = try v.decodeIfPresent(Double.self, forKey: .pinOpacity) ?? pinOpacity
        pinAllSpaces = try v.decodeIfPresent(Bool.self, forKey: .pinAllSpaces) ?? pinAllSpaces
        pinShadow = try v.decodeIfPresent(Bool.self, forKey: .pinShadow) ?? pinShadow
        pinUnlockKey = (try? v.decodeIfPresent(PinUnlockKey.self, forKey: .pinUnlockKey)) ?? .option
    }
    public var isValid: Bool {
        [0, 5, 10, 20, 30].contains(thumbnailSeconds) && (200...360).contains(thumbnailWidth)
            && (240...1000).contains(pinSize) && (0.2...1).contains(pinOpacity)
    }
}

/// Ask: chat about a capture through a subscription CLI. See `AI/Assistant`.
public struct AssistantPreferences: Codable, Equatable, Sendable {
    /// "chatgpt" (default), "claude", or "off". Raw values of `AssistantProvider` plus "off".
    public var provider: String = "chatgpt"
    /// nil uses the tool's own default model.
    public var model: String?
    public var confirmBeforeSending = true
    public var includeRecognizedText = true
    public var redactBeforeSending = false
    public var keepConversations = true
    /// Suggestion chips shown under a new conversation, editable in Settings.
    public var suggestions: [String] = AssistantPreferences.defaultSuggestions
    /// The one-tap actions above the typing bar. Built-in titles carry a full prompt (see `AskQuickAction`).
    public static let defaultSuggestions = ["Solve", "Explain", "Suggest", "Improve"]
    /// 0.1.0's defaults, replaced on load when the user never changed them.
    static let legacyDefaultSuggestions = ["Explain this", "Summarize", "What should I do next?", "Write alt text"]
    public init() {}
    public init(from decoder: Decoder) throws {
        self.init()
        let v = try decoder.container(keyedBy: CodingKeys.self)
        provider = try v.decodeIfPresent(String.self, forKey: .provider) ?? "chatgpt"
        model = try v.decodeIfPresent(String.self, forKey: .model)
        confirmBeforeSending = try v.decodeIfPresent(Bool.self, forKey: .confirmBeforeSending) ?? true
        includeRecognizedText = try v.decodeIfPresent(Bool.self, forKey: .includeRecognizedText) ?? true
        redactBeforeSending = try v.decodeIfPresent(Bool.self, forKey: .redactBeforeSending) ?? false
        keepConversations = try v.decodeIfPresent(Bool.self, forKey: .keepConversations) ?? true
        var saved = try v.decodeIfPresent([String].self, forKey: .suggestions) ?? Self.defaultSuggestions
        if saved == Self.legacyDefaultSuggestions { saved = Self.defaultSuggestions }
        var seen = Set<String>()
        suggestions = saved.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        if !["chatgpt", "claude", "off"].contains(provider) { provider = "chatgpt" }
    }
    public var availableProvider: AssistantProvider? { Assistant.availableProvider(named: provider) }
    public var isEnabled: Bool { availableProvider != nil }
}

/// Interface choices beyond light and dark. Every field decodes optionally.
public struct CustomizationPreferences: Codable, Equatable, Sendable {
    public var accent: DS.AccentChoice = .blue
    public var density: DS.Density = .regular
    /// Floating chrome: system glass, or a solid tinted surface.
    public var chrome: DS.Chrome = .glass
    /// Editor tool palette, in order: "select", "crop", then `LayerKind` raw values. Missing ids are hidden.
    public var editorTools: [String] = CustomizationPreferences.defaultEditorTools
    /// Buttons on the area-selection action bar, in order.
    public var overlayActions: [String] = CustomizationPreferences.defaultOverlayActions
    /// Hover buttons on the quick-access thumbnail, in order.
    public var thumbnailActions: [String] = CustomizationPreferences.defaultThumbnailActions
    /// Show text labels under the area-selection action bar buttons.
    public var overlayLabels = true
    public static let defaultEditorTools = ["select", "crop", "arrow", "rectangle", "oval", "line", "text", "counter", "drawing", "highlighter", "blur", "pixelate", "erase", "spotlight", "magnifier", "ruler", "picker", "image"]
    public static let allOverlayActions = ["capture", "copy", "save", "edit", "pin", "text", "ask"]
    public static let defaultOverlayActions = ["capture", "copy", "save", "edit", "pin", "text", "ask"]
    public static let allThumbnailActions = ["copy", "save", "pin", "ask", "edit", "delete"]
    public static let defaultThumbnailActions = ["edit", "copy", "save", "pin", "ask", "delete"]
    public init() {}
    public init(from decoder: Decoder) throws {
        self.init()
        let v = try decoder.container(keyedBy: CodingKeys.self)
        accent = try v.decodeIfPresent(DS.AccentChoice.self, forKey: .accent) ?? .blue
        density = try v.decodeIfPresent(DS.Density.self, forKey: .density) ?? .regular
        chrome = try v.decodeIfPresent(DS.Chrome.self, forKey: .chrome) ?? .glass
        editorTools = CustomizationList.editor.normalized(try v.decodeIfPresent([String].self, forKey: .editorTools) ?? Self.defaultEditorTools)
        overlayActions = CustomizationList.overlay.normalized(try v.decodeIfPresent([String].self, forKey: .overlayActions) ?? Self.defaultOverlayActions)
        let savedThumbnailActions = try v.decodeIfPresent([String].self, forKey: .thumbnailActions)
        thumbnailActions = CustomizationList.thumbnail.normalized(
            savedThumbnailActions == ["copy", "save", "pin", "ask", "delete"] ? Self.defaultThumbnailActions : savedThumbnailActions ?? Self.defaultThumbnailActions)
        overlayLabels = try v.decodeIfPresent(Bool.self, forKey: .overlayLabels) ?? true
    }
}

public struct Preferences: Codable, Equatable, Sendable {
    public var appearance: AppAppearance = .system
    public var assistant = AssistantPreferences()
    public var customization = CustomizationPreferences()
    public var showDockIcon = false
    public var onboardingCompleted = false
    public var floating = FloatingPreferences()
    public var afterCapture: Set<AfterCapture> = [.thumbnail]
    public var autoCopyScreenshots = false
    public var captureOnRelease = false
    public var areaAction: AfterCapture = .thumbnail
    public var includeCursor = false
    public var historyEnabled = true
    public var organizeCapturesLocally = false
    public var useAppleIntelligenceForOrganization = true
    public var retentionDays = 30
    public var fileFormat: String = "public.png"
    public var clipboardFormat: String = "public.png"
    public var quality: Double = 1
    public var oneX: Bool = false
    public var convertToSRGB: Bool = false
    public var filenameTemplate: String = "{app} {date} {time} {counter}"
    public var filenameCounter: Int = 1
    public var subfolders: String = "none"
    public var saveSidecar: Bool = false
    public var keepExportUpdated = false
    public var captureSound: Bool = false
    public var captureSoundName: String?
    public var selectionTint: RGBA?
    public var selectionTintOpacity: Double?
    public var hideDesktopIcons: Bool = false
    public var keepWindowShadow: Bool = false
    public var automaticBackdrop: Bool = false
    public var defaultBackdrop: Backdrop = Backdrop()
    public var backdropPresets: [BackdropPreset] = []
    public var modeActions: [String: Set<AfterCapture>] = [:]
    public var toolShortcuts: [String: String] = [:]
    public var shortcuts = Shortcut.defaults
    public var saveFolder = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!.appendingPathComponent("SuperShot").path
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case floating, assistant, customization
        case autoCopyScreenshots, captureOnRelease
        case keepExportUpdated, organizeCapturesLocally, useAppleIntelligenceForOrganization
        case captureSoundName, selectionTint, selectionTintOpacity
        case appearance, showDockIcon, onboardingCompleted, afterCapture, areaAction, includeCursor, saveFolder, shortcuts, historyEnabled, retentionDays, fileFormat, clipboardFormat, quality, oneX, convertToSRGB, filenameTemplate, filenameCounter, subfolders, saveSidecar, captureSound, hideDesktopIcons, keepWindowShadow, automaticBackdrop, defaultBackdrop, backdropPresets, modeActions, toolShortcuts
    }
    public init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        appearance = try values.decodeIfPresent(AppAppearance.self, forKey: .appearance) ?? .system
        showDockIcon = try values.decodeIfPresent(Bool.self, forKey: .showDockIcon) ?? false
        onboardingCompleted = try values.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
        floating = try values.decodeIfPresent(FloatingPreferences.self, forKey: .floating) ?? FloatingPreferences()
        assistant = try values.decodeIfPresent(AssistantPreferences.self, forKey: .assistant) ?? AssistantPreferences()
        customization = try values.decodeIfPresent(CustomizationPreferences.self, forKey: .customization) ?? CustomizationPreferences()
        afterCapture = try values.decodeIfPresent(Set<AfterCapture>.self, forKey: .afterCapture) ?? [.thumbnail]
        autoCopyScreenshots = try values.decodeIfPresent(Bool.self, forKey: .autoCopyScreenshots) ?? false
        captureOnRelease = try values.decodeIfPresent(Bool.self, forKey: .captureOnRelease) ?? false
        areaAction = try values.decodeIfPresent(AfterCapture.self, forKey: .areaAction) ?? .thumbnail
        shortcuts = try values.decodeIfPresent([String: Shortcut].self, forKey: .shortcuts) ?? Shortcut.defaults
        fileFormat = try values.decodeIfPresent(String.self, forKey: .fileFormat) ?? "public.png"
        clipboardFormat = try values.decodeIfPresent(String.self, forKey: .clipboardFormat) ?? "public.png"
        quality = try values.decodeIfPresent(Double.self, forKey: .quality) ?? 1
        oneX = try values.decodeIfPresent(Bool.self, forKey: .oneX) ?? false
        convertToSRGB = try values.decodeIfPresent(Bool.self, forKey: .convertToSRGB) ?? false
        filenameTemplate = try values.decodeIfPresent(String.self, forKey: .filenameTemplate) ?? "{app} {date} {time} {counter}"
        filenameCounter = try values.decodeIfPresent(Int.self, forKey: .filenameCounter) ?? 1
        subfolders = try values.decodeIfPresent(String.self, forKey: .subfolders) ?? "none"
        saveSidecar = try values.decodeIfPresent(Bool.self, forKey: .saveSidecar) ?? false
        captureSound = try values.decodeIfPresent(Bool.self, forKey: .captureSound) ?? false
        captureSoundName = try values.decodeIfPresent(String.self, forKey: .captureSoundName)
        if let captureSoundName, !Self.captureSoundNames.contains(captureSoundName) { self.captureSoundName = nil }
        selectionTint = try values.decodeIfPresent(RGBA.self, forKey: .selectionTint)
        selectionTintOpacity = try values.decodeIfPresent(Double.self, forKey: .selectionTintOpacity)
        if let selectionTintOpacity, !(0...0.40).contains(selectionTintOpacity) { self.selectionTintOpacity = nil }
        keepExportUpdated = try values.decodeIfPresent(Bool.self, forKey: .keepExportUpdated) ?? false
        organizeCapturesLocally = try values.decodeIfPresent(Bool.self, forKey: .organizeCapturesLocally) ?? false
        useAppleIntelligenceForOrganization = try values.decodeIfPresent(Bool.self, forKey: .useAppleIntelligenceForOrganization) ?? true
        hideDesktopIcons = try values.decodeIfPresent(Bool.self, forKey: .hideDesktopIcons) ?? false
        keepWindowShadow = try values.decodeIfPresent(Bool.self, forKey: .keepWindowShadow) ?? false
        automaticBackdrop = try values.decodeIfPresent(Bool.self, forKey: .automaticBackdrop) ?? false
        backdropPresets = try values.decodeIfPresent([BackdropPreset].self,forKey:.backdropPresets) ?? []
        defaultBackdrop = try values.decodeIfPresent(Backdrop.self, forKey: .defaultBackdrop) ?? Backdrop()
        modeActions = try values.decodeIfPresent([String: Set<AfterCapture>].self, forKey: .modeActions) ?? [:]
        toolShortcuts = try values.decodeIfPresent([String: String].self, forKey: .toolShortcuts) ?? [:]
        historyEnabled = try values.decodeIfPresent(Bool.self, forKey: .historyEnabled) ?? true
        retentionDays = try values.decodeIfPresent(Int.self, forKey: .retentionDays) ?? 30
        includeCursor = try values.decodeIfPresent(Bool.self, forKey: .includeCursor) ?? false
        saveFolder = try values.decodeIfPresent(String.self, forKey: .saveFolder) ?? saveFolder
        guard floating.isValid,filenameCounter>=0,filenameCounter<Int.max,quality.isFinite,(0...1).contains(quality),(0...36500).contains(retentionDays),[.editor,.thumbnail,.copy].contains(areaAction),!saveFolder.isEmpty,saveFolder.hasPrefix("/") else {
            throw DecodingError.dataCorrupted(.init(codingPath:decoder.codingPath,debugDescription:"Invalid preference values"))
        }
        try ShortcutProfile(global:shortcuts,editor:toolShortcuts).validate()
        for backdrop in [defaultBackdrop]+backdropPresets.map(\.backdrop) {
            var probe=CaptureDocument(original:Data(),width:1,height:1);probe.backdrop=backdrop
            _ = try ProjectFile.decode(ProjectFile.encode(probe))
        }
    }

    public static let captureSoundNames = ["Tink", "Pop", "Glass", "Hero"]

    /// Auto-copy is additive, including when a mode or an overlay button overrides
    /// the other actions. OCR and barcode workflows never enter this image path.
    public func actions(for mode: CaptureActionMode, override: Set<AfterCapture>? = nil) -> Set<AfterCapture> {
        var actions = override ?? (mode == .area ? [areaAction] : modeActions[mode.rawValue] ?? afterCapture)
        if autoCopyScreenshots { actions.insert(.copy) }
        return actions
    }
}

@MainActor @Observable public final class SettingsStore {
    public static let storageKey = "SuperShot.preferences.v1"
    public static let recoveryKey = "SuperShot.preferences.recovery"
    public static let fullQualityKey = "SuperShot.preferences.fullQuality.v1"
    // Separate from the preferences payload: closing setup or recovering damaged settings
    // must not turn a subsequent launch into another first run.
    public static let setupSeenKey = "SuperShot.setupSeen.v1"
    public var preferences: Preferences { didSet { save() } }
    public var isRecordingShortcut = false
    public var shortcutError: String?
    public private(set) var recoveryMessage: String?
    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey) {
            do {
                var stored = try JSONDecoder().decode(Preferences.self, from: data)
                // One-time move to full-quality output for settings saved before it became the default.
                if !defaults.bool(forKey: Self.fullQualityKey) {
                    stored.quality = 1; stored.convertToSRGB = false; stored.oneX = false
                }
                preferences = stored
            }
            catch {
                defaults.set(data, forKey: Self.recoveryKey)
                preferences = Preferences()
                recoveryMessage = "Your previous preferences could not be read. A backup was kept and defaults restored."
            }
        } else { preferences = Preferences() }
        if !defaults.bool(forKey: Self.fullQualityKey) { defaults.set(true, forKey: Self.fullQualityKey); save() }
    }

    public func claimFirstLaunchSetup(screenAccess: Bool) -> Bool {
        let shouldShow = !defaults.bool(forKey: Self.setupSeenKey) && !preferences.onboardingCompleted && !screenAccess
        defaults.set(true, forKey: Self.setupSeenKey)
        return shouldShow
    }

    private func save() {
        do { defaults.set(try JSONEncoder().encode(preferences), forKey: Self.storageKey) }
        catch { recoveryMessage = "Your preferences could not be saved: \(error.localizedDescription)" }
    }
}
