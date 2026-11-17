# Apple API checks — 2026-11-15

Environment: macOS 27.2 (26B5101f), Swift 6.4, Command Line Tools SDK macOS 27.0. Deployment floor remains 26.0.

- NSGlassEffectView: https://developer.apple.com/documentation/appkit/nsglasseffectview.md . Available from macOS 26. SDK header confirms contentView, cornerRadius, regular/clear style. `effectIsInteractive` is macOS 27 only and is not used.
- SwiftUI glassEffect uses the native material; Reduce Transparency behavior is delegated to the system.
- CGRequestScreenCaptureAccess: https://developer.apple.com/documentation/coregraphics/cgrequestscreencaptureaccess().md . SDK CGWindow.h confirms a denied process is not re-prompted and must use System Settings.
- CGPreflightScreenCaptureAccess: https://developer.apple.com/documentation/coregraphics/cgpreflightscreencaptureaccess() . Used for refresh, including app activation; tests inject the probe to cover grant and revocation.
- The System Settings URL is a convenience deep link; it is not an authorization API.
- Periodic reauthorization timing on macOS 26/27 is not established by this run. Do not promise permanent grants or a specific reprompt interval. The UI refreshes the observed state and permits reopening privacy settings.

Toolchain notes: default XCTest import is absent under this CLT installation. Tests use Swift Testing and scripts/test.sh supplies the bundled Testing macro plugin explicitly. The macOS 27 SDK exports both a State macro and wrapper, but CLT omits SwiftUIMacros; a `ViewState<Value>` typealias selects the supported property wrapper while retaining macOS 26 compatibility.

## Final audit checks — 2026-11-16

- [RecognizeTextRequest.minimumTextHeightFraction](https://developer.apple.com/documentation/vision/recognizetextrequest/minimumtextheightfraction.md): Apple's current documentation confirms a default fraction of 1/32. This excludes ordinary interface text on large screenshots in the fast path. The implementation now uses a fraction corresponding to eight source pixels, capped at one for tiny images. The installed SDK confirms the Swift property name.
- [SCScreenshotManager](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager.md): confirms filtered single-frame capture via `captureImage(contentFilter:configuration:completionHandler:)`; Swift concurrency imports the async form used by CaptureService.
- [SMAppService.mainApp](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp.md): confirms that this service configures the main app as a login item. Registration exists in Settings; actual login/restart behavior remains unverified.
