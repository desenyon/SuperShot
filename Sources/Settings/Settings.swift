import Foundation
import Observation
import Hotkeys
import Document

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
    case screen, window, area, scrolling
}

public enum ThumbnailCorner: String, Codable, CaseIterable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight
    public var title: String {
        switch self { case .topLeft: "Top left"; case .topRight: "Top right"; case .bottomLeft: "Bottom left"; case .bottomRight: "Bottom right" }
    }
    public var isRight: Bool { self == .topRight || self == .bottomRight }
    public var isTop: Bool { self == .topLeft || self == .topRight }
}

public struct FloatingPreferences: Codable, Equatable, Sendable {
    public var thumbnailCorner: ThumbnailCorner = .bottomRight
    public var thumbnailSeconds: Int = 0
    public var thumbnailWidth: Double = 264
    public var pinSize: Double = 520
    public var pinOpacity: Double = 1
    public var pinAllSpaces = true
    public var pinShadow = true
    public init() {}
    public var isValid: Bool {
        [0, 5, 10, 20, 30].contains(thumbnailSeconds) && (200...360).contains(thumbnailWidth)
            && (240...1000).contains(pinSize) && (0.2...1).contains(pinOpacity)
    }
}

public struct Preferences: Codable, Equatable, Sendable {
    public var appearance: AppAppearance = .system
    public var showDockIcon = false
    public var onboardingCompleted = false
    public var floating = FloatingPreferences()
    public var afterCapture: Set<AfterCapture> = [.thumbnail]
    public var autoCopyScreenshots = false
    public var captureOnRelease = false
    public var areaAction: AfterCapture = .thumbnail
    public var includeCursor = false
    public var historyEnabled = true
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
    public var captureSound: Bool = false
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
        case floating
        case autoCopyScreenshots, captureOnRelease
        case appearance, showDockIcon, onboardingCompleted, afterCapture, areaAction, includeCursor, saveFolder, shortcuts, historyEnabled, retentionDays, fileFormat, clipboardFormat, quality, oneX, convertToSRGB, filenameTemplate, filenameCounter, subfolders, saveSidecar, captureSound, hideDesktopIcons, keepWindowShadow, automaticBackdrop, defaultBackdrop, backdropPresets, modeActions, toolShortcuts
    }
    public init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        appearance = try values.decodeIfPresent(AppAppearance.self, forKey: .appearance) ?? .system
        showDockIcon = try values.decodeIfPresent(Bool.self, forKey: .showDockIcon) ?? false
        onboardingCompleted = try values.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
        floating = try values.decodeIfPresent(FloatingPreferences.self, forKey: .floating) ?? FloatingPreferences()
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
