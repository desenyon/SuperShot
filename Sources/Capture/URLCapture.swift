import AppKit
import CoreGraphics
import Darwin
import Foundation
import ImageIO

public struct URLCaptureRequest: Sendable {
    public enum Appearance: String, CaseIterable, Sendable { case light, dark }
    public enum Scope: String, CaseIterable, Sendable { case viewport, fullPage }

    public static let viewportRange = 128...4096
    static let maximumPixels = 24_000_000
    static let maximumPageHeight = 16_384

    public let url: URL
    public let width: Int
    public let height: Int
    public let appearance: Appearance
    public let scope: Scope
    /// History and suggested filenames should not contain URL paths, parameters, or credentials.
    public var source: String { url.host(percentEncoded: false) ?? "Webpage" }

    public init(address: String, width: Int, height: Int, appearance: Appearance, scope: Scope) throws {
        self.url = try Self.parseAddress(address)
        guard Self.viewportRange.contains(width), Self.viewportRange.contains(height) else {
            throw URLCaptureError.invalidSize
        }
        self.width = width
        self.height = height
        self.appearance = appearance
        self.scope = scope
    }

    public static func parseAddress(_ address: String) throws -> URL {
        let input = address.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty, input.utf8.count <= 8192, !input.contains("\\"),
              !input.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }) else {
            throw URLCaptureError.invalidAddress
        }
        let authority = input.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        let explicitScheme = authority.last == ":"
        let candidate = explicitScheme ? input : "https://" + input
        guard var components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.port.map({ (1...65_535).contains($0) }) ?? true else { throw URLCaptureError.invalidAddress }
        if !explicitScheme, ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host.lowercased()) {
            components.scheme = "http"
        }
        guard let url = components.url else { throw URLCaptureError.invalidAddress }
        return url
    }

    func captureHeight(contentHeight: Double) throws -> Int {
        guard scope == .fullPage else { return height }
        let pixels = max(Double(height), contentHeight.rounded(.up))
        guard contentHeight.isFinite, contentHeight > 0,
              pixels <= Double(Self.maximumPageHeight), pixels * Double(width) <= Double(Self.maximumPixels) else {
            throw URLCaptureError.pageTooLarge
        }
        return Int(pixels)
    }
}

public enum URLCaptureError: LocalizedError, Equatable {
    case invalidAddress, invalidSize, pageTooLarge, browserMissing, browserUnavailable
    case timedOut, navigationFailed, pageUnavailable, invalidImage

    public var errorDescription: String? {
        switch self {
        case .invalidAddress: "Enter a valid HTTP or HTTPS address."
        case .invalidSize: "Width and height must be between 128 and 4096 pixels."
        case .pageTooLarge: "This page is too large to capture at this width. Try a narrower viewport or capture the visible area."
        case .browserMissing: "Webpage capture requires an installed copy of Chrome, Chromium, Edge, or Brave."
        case .browserUnavailable: "The browser couldn’t start in a temporary profile. Check that it’s installed and up to date."
        case .timedOut: "The webpage took too long to capture. Try again or choose Visible Area."
        case .navigationFailed: "The browser couldn’t load this address. Check the URL and your connection, then try again."
        case .pageUnavailable: "The browser couldn’t render this webpage."
        case .invalidImage: "The browser returned an unreadable screenshot."
        }
    }
}

/// Renders HTTP(S) pages locally with an installed browser and disposable, isolated profile.
public struct URLCaptureService: Sendable {
    private let executable: URL?
    private let timeout: Duration
    public let browserName: String?

    public init() {
        let browser = Self.installedBrowser()
        self.init(executable: browser?.url, timeout: .seconds(35), browserName: browser?.name)
    }

    init(executable: URL?, timeout: Duration, browserName: String? = nil) {
        self.executable = executable
        self.timeout = timeout
        self.browserName = browserName
    }

    public static var browserAvailable: Bool { installedBrowser() != nil }

    private static func installedBrowser() -> (name: String, url: URL)? {
        let fm = FileManager.default
        let browsers = [
            ("Google Chrome", "com.google.Chrome"),
            ("Chromium", "org.chromium.Chromium"),
            ("Microsoft Edge", "com.microsoft.edgemac"),
            ("Brave Browser", "com.brave.Browser"),
            ("Google Chrome Beta", "com.google.Chrome.beta"),
            ("Google Chrome Canary", "com.google.Chrome.canary")
        ]
        let directories = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
        for (name, identifier) in browsers {
            let registered = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
            let conventional = directories.map { $0.appendingPathComponent("\(name).app", isDirectory: true) }
            for location in [registered].compactMap(\.self) + conventional {
                if let bundle = Bundle(url: location), bundle.bundleIdentifier == identifier,
                   let binary = bundle.executableURL, fm.isExecutableFile(atPath: binary.path) {
                    return (name, binary)
                }
            }
        }
        return nil
    }

    public func capture(_ request: URLCaptureRequest) async throws -> CapturedImage {
        guard let executable else { throw URLCaptureError.browserMissing }
        return try await withThrowingTaskGroup(of: CapturedImage.self) { group in
            group.addTask { try await Self.render(request, with: executable) }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw URLCaptureError.timedOut
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw CancellationError() }
            try Task.checkCancellation()
            return result
        }
    }

    private static func render(_ request: URLCaptureRequest, with executable: URL) async throws -> CapturedImage {
        try Task.checkCancellation()
        let profile = FileManager.default.temporaryDirectory.appendingPathComponent("SuperShot-Webpage-\(UUID())")
        do {
            try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
        } catch { throw URLCaptureError.browserUnavailable }

        let browser = Process()
        let exited = DispatchSemaphore(value: 0)
        browser.terminationHandler = { _ in exited.signal() }
        browser.executableURL = executable
        browser.arguments = [
            "--headless", "--no-first-run", "--no-default-browser-check",
            "--disable-background-networking", "--disable-component-update", "--disable-extensions",
            "--disable-default-apps", "--disable-sync", "--disable-crash-reporter", "--metrics-recording-only",
            "--disable-notifications", "--mute-audio", "--use-mock-keychain",
            "--disable-background-timer-throttling", "--disable-renderer-backgrounding",
            "--remote-debugging-address=127.0.0.1", "--remote-debugging-port=0",
            "--user-data-dir=\(profile.path)", "about:blank"
        ]
        browser.standardInput = FileHandle.nullDevice
        browser.standardOutput = FileHandle.nullDevice
        browser.standardError = FileHandle.nullDevice
        var closingGracefully = false
        defer {
            stopBrowser(browser, exited: exited, closingGracefully: closingGracefully)
            do {
                try FileManager.default.removeItem(at: profile)
            } catch {
                // A Chromium helper can remove profile files while the recursive deletion runs.
                try? FileManager.default.removeItem(at: profile)
            }
        }
        do { try browser.run() } catch { throw URLCaptureError.browserUnavailable }

        let endpointFile = profile.appendingPathComponent("DevToolsActivePort")
        while true {
            try Task.checkCancellation()
            guard browser.isRunning else { throw URLCaptureError.browserUnavailable }
            if let contents = try? String(contentsOf: endpointFile, encoding: .utf8),
               let endpoint = devToolsEndpoint(contents) {
                let result = try await BrowserCaptureSession(endpoint: endpoint).capture(request)
                closingGracefully = true
                return result
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private static func stopBrowser(_ browser: Process, exited: DispatchSemaphore, closingGracefully: Bool) {
        guard browser.isRunning else { return }
        if closingGracefully, exited.wait(timeout: .now() + .milliseconds(500)) == .success { return }
        guard browser.isRunning else { return }
        browser.terminate()
        if exited.wait(timeout: .now() + .seconds(2)) == .timedOut, browser.isRunning {
            kill(browser.processIdentifier, SIGKILL)
        }
        browser.waitUntilExit()
    }

    static func devToolsEndpoint(_ contents: String) -> URL? {
        let lines = contents.split(whereSeparator: \.isNewline)
        guard lines.count == 2, let port = Int(lines[0]), (1...65_535).contains(port) else { return nil }
        let prefix = "/devtools/browser/"
        guard lines[1].hasPrefix(prefix) else { return nil }
        let token = lines[1].dropFirst(prefix.count)
        guard !token.isEmpty, token.utf8.count <= 80,
              token.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 }) else { return nil }
        return URL(string: "ws://127.0.0.1:\(port)\(lines[1])")
    }
}

private final class BrowserCaptureSession {
    private let session: URLSession
    private let socket: URLSessionWebSocketTask
    private var identifier = 0
    private var targetSession: String?
    private var readyDocuments: Set<String> = []

    init(endpoint: URL) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        self.session = URLSession(configuration: configuration)
        self.socket = session.webSocketTask(with: endpoint)
        // PNGs arrive as base64, so allow space for the encoded 24 MP limit.
        self.socket.maximumMessageSize = URLCaptureRequest.maximumPixels * 6 + 1_000_000
    }

    func capture(_ request: URLCaptureRequest) async throws -> CapturedImage {
        let socket = self.socket
        defer { session.invalidateAndCancel() }
        return try await withTaskCancellationHandler {
            socket.resume()
            do {
                let result = try await render(request)
                // The browser-level close lets its workers finish with the temporary profile.
                targetSession = nil
                _ = try? await command("Browser.close")
                return result
            } catch let error as URLCaptureError {
                throw error
            } catch {
                try Task.checkCancellation()
                throw URLCaptureError.browserUnavailable
            }
        } onCancel: {
            socket.cancel(with: .goingAway, reason: nil)
        }
    }

    private func render(_ request: URLCaptureRequest) async throws -> CapturedImage {
        _ = try await command("Browser.setDownloadBehavior", ["behavior": "deny"])
        let target = try await command("Target.createTarget", ["url": "about:blank"])
        guard let targetID = target["targetId"] as? String else { throw URLCaptureError.browserUnavailable }
        let attached = try await command("Target.attachToTarget", ["targetId": targetID, "flatten": true])
        guard let sessionID = attached["sessionId"] as? String else { throw URLCaptureError.browserUnavailable }
        targetSession = sessionID

        _ = try await command("Page.enable")
        _ = try await command("Page.setLifecycleEventsEnabled", ["enabled": true])
        _ = try await command("Emulation.setDeviceMetricsOverride", [
            "width": request.width, "height": request.height,
            "deviceScaleFactor": 1, "mobile": false
        ])
        _ = try await command("Emulation.setScrollbarsHidden", ["hidden": true])
        _ = try await command("Emulation.setEmulatedMedia", [
            "features": [["name": "prefers-color-scheme", "value": request.appearance.rawValue]]
        ])

        let navigation = try await command("Page.navigate", ["url": request.url.absoluteString])
        guard navigation["errorText"] == nil, navigation["isDownload"] as? Bool != true,
              let loaderID = navigation["loaderId"] as? String,
              let frameID = navigation["frameId"] as? String else { throw URLCaptureError.navigationFailed }
        while !readyDocuments.contains(loaderID) { _ = try await receive() }

        let fullPage = request.scope == .fullPage
        let initialHeight = fullPage ? try await documentHeight(for: request) : request.height
        try await prepareFrame(frameID, scrollHeight: fullPage ? initialHeight : 0)

        let height = fullPage ? try await documentHeight(for: request) : request.height
        var parameters: [String: Any] = ["format": "png", "captureBeyondViewport": fullPage]
        if fullPage {
            parameters["clip"] = ["x": 0, "y": 0, "width": request.width, "height": height, "scale": 1]
        }

        let shot = try await command("Page.captureScreenshot", parameters)
        guard let encoded = shot["data"] as? String, let data = Data(base64Encoded: encoded),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              properties[kCGImagePropertyPixelWidth] as? Int == request.width,
              properties[kCGImagePropertyPixelHeight] as? Int == height,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw URLCaptureError.invalidImage }
        return CapturedImage(image: image, scale: 1, source: request.source)
    }

    private func documentHeight(for request: URLCaptureRequest) async throws -> Int {
        let layout = try await command("Page.getLayoutMetrics")
        guard let size = layout["cssContentSize"] as? [String: Any],
              let contentHeight = size["height"] as? Double else { throw URLCaptureError.pageUnavailable }
        return try request.captureHeight(contentHeight: contentHeight)
    }

    private func prepareFrame(_ frameID: String, scrollHeight: Int) async throws {
        let world = try await command("Page.createIsolatedWorld", ["frameId": frameID, "worldName": "SuperShot"])
        guard let contextID = world["executionContextId"] as? Int else { throw URLCaptureError.pageUnavailable }
        // A slow image should never hold the whole capture, while a full-page capture
        // should reveal content whose loading depends on entering the viewport.
        let script = """
            (async () => {
              const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
              const paint = async () => {
                await Promise.race([
                  new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))),
                  pause(160)
                ]);
                // IntersectionObserver callbacks run in a separate task after the frame.
                await pause(24);
              };
              const fullHeight = \(scrollHeight);
              if (fullHeight > innerHeight) {
                const distance = fullHeight - innerHeight;
                const steps = Math.min(28, Math.ceil(distance / (innerHeight * 0.85)));
                for (let step = 1; step <= steps; step++) {
                  scrollTo({top: distance * step / steps, behavior: 'instant'});
                  await paint();
                }
                await pause(140);
                scrollTo({top: 0, behavior: 'instant'});
              }
              const bottom = fullHeight || innerHeight;
              const images = Array.from(document.images).filter(image => {
                const rect = image.getBoundingClientRect();
                return rect.height > 0 && rect.bottom > 0 && rect.top < bottom;
              }).slice(0, 80);
              await Promise.race([
                Promise.allSettled([document.fonts?.ready, ...images.map(image => image.decode())]),
                pause(850)
              ]);
              await paint();
            })()
            """
        let response = try await command("Runtime.evaluate", [
            "expression": script, "contextId": contextID, "awaitPromise": true
        ])
        guard response["exceptionDetails"] == nil else { throw URLCaptureError.pageUnavailable }
    }

    private func command(_ method: String, _ parameters: [String: Any] = [:]) async throws -> [String: Any] {
        let id = try await send(method, parameters)
        while true {
            let response = try await receive()
            guard response["id"] as? Int == id else { continue }
            guard response["error"] == nil, let result = response["result"] as? [String: Any] else {
                throw URLCaptureError.pageUnavailable
            }
            return result
        }
    }

    private func send(_ method: String, _ parameters: [String: Any]) async throws -> Int {
        try Task.checkCancellation()
        identifier += 1
        let id = identifier
        var request: [String: Any] = ["id": id, "method": method, "params": parameters]
        if let targetSession { request["sessionId"] = targetSession }
        let payload = try JSONSerialization.data(withJSONObject: request)
        try await socket.send(.string(String(decoding: payload, as: UTF8.self)))
        return id
    }

    private func receive() async throws -> [String: Any] {
        try Task.checkCancellation()
        let data: Data
        switch try await socket.receive() {
        case .string(let message): data = Data(message.utf8)
        case .data(let message): data = message
        @unknown default: throw URLCaptureError.pageUnavailable
        }
        guard let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLCaptureError.pageUnavailable
        }
        guard let targetSession, decoded["sessionId"] as? String == targetSession else { return decoded }
        if decoded["method"] as? String == "Page.lifecycleEvent",
           let event = decoded["params"] as? [String: Any],
           let name = event["name"] as? String, name == "DOMContentLoaded" || name == "load",
           let loader = event["loaderId"] as? String {
            readyDocuments.insert(loader)
        } else if decoded["method"] as? String == "Page.javascriptDialogOpening" {
            _ = try await send("Page.handleJavaScriptDialog", ["accept": false])
        }
        return decoded
    }
}
