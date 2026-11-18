import AppKit
import SwiftUI
import ScreenCaptureKit
import DesignSystem
import Export
import Render

/// Shows preview scenes in real windows so system Liquid Glass renders, then captures each window with
/// ScreenCaptureKit. Used to verify glass, which offscreen renders cannot show. Each window is on screen
/// for about a second. Run from the signed bundle so the existing Screen Recording grant applies:
/// `SuperShot.app/Contents/MacOS/SuperShot --live-preview <output-dir> <fixture.png>` (PREVIEW_ONLY filters scenes).
@MainActor enum LiveRenderer {
    static func run(output: URL, fixture: URL) async {
        DS.rendersOffscreen = false
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        guard let data = try? Data(contentsOf: fixture), let image = DocumentRenderer.decode(data) else {
            FileHandle.standardError.write(Data("Could not read fixture image\n".utf8)); return
        }
        let filters = ProcessInfo.processInfo.environment["PREVIEW_ONLY"]?.split(separator: ",").map(String.init) ?? []
        let scenes = PreviewRenderer.scenes(data: data, image: image).filter { scene in filters.contains { scene.name.contains($0) } }
        for dark in [true, false] {
            for scene in scenes {
                let url = output.appendingPathComponent("live-\(scene.name)-\(dark ? "dark" : "light").png")
                do { try await capture(scene.view, size: scene.size, dark: dark, to: url); print("Captured \(url.lastPathComponent)") }
                catch { FileHandle.standardError.write(Data("\(scene.name): \(error)\n".utf8)) }
            }
        }
    }

    private static func capture(_ view: AnyView, size: CGSize, dark: Bool, to url: URL) async throws {
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let fitted = CGSize(width: min(size.width, screen.width - DS.xxl), height: min(size.height, screen.height - DS.xxl))
        let window = NSWindow(contentRect: CGRect(x: screen.midX - fitted.width / 2, y: screen.midY - fitted.height / 2,
                                                  width: fitted.width, height: fitted.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.isReleasedWhenClosed = false; window.level = .floating; window.hasShadow = false
        window.isOpaque = false; window.backgroundColor = .clear
        window.contentView = NSHostingView(rootView: view.frame(width: fitted.width, height: fitted.height))
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(900)) // let glass and entrance animations settle
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let target = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
            throw CocoaError(.featureUnsupported, userInfo: [NSLocalizedDescriptionKey: "Preview window not found in shareable content"])
        }
        let configuration = SCStreamConfiguration()
        let scale = window.backingScaleFactor
        configuration.width = Int(fitted.width * scale); configuration.height = Int(fitted.height * scale)
        configuration.showsCursor = false; configuration.ignoreShadowsSingleWindow = true
        let shot = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: target), configuration: configuration)
        try ImageExport.encode(shot).write(to: url)
    }
}
