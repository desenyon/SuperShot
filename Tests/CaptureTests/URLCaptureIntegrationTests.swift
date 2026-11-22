import CoreGraphics
import Foundation
import Network
import Testing
@testable import Capture

@Suite(.enabled(if: ProcessInfo.processInfo.environment["SUPERSHOT_TEST_WEBPAGE"] == "1" &&
    URLCaptureService.browserAvailable, "Opt in with SUPERSHOT_TEST_WEBPAGE=1 and install a Chromium-family browser."))
struct URLCaptureIntegrationTests {
    @Test func capturesLiveCSSBreakpointsAppearanceAndFullPageFromLoopback() async throws {
        let listener = try LoopbackWebpage()
        defer { listener.stop() }
        let address = try await listener.start()
        let service = URLCaptureService()

        let phone = try await service.capture(URLCaptureRequest(address: address, width: 390, height: 500,
                                                                appearance: .dark, scope: .viewport))
        #expect(phone.image.width == 390 && phone.image.height == 500)
        #expect(try rgb(phone.image) == [0, 255, 119])

        let desktop = try await service.capture(URLCaptureRequest(address: address, width: 800, height: 600,
                                                                   appearance: .dark, scope: .viewport))
        #expect(desktop.image.width == 800 && desktop.image.height == 600)
        #expect(try rgb(desktop.image) == [0, 119, 221])

        let full = try await service.capture(URLCaptureRequest(address: address, width: 800, height: 600,
                                                                appearance: .light, scope: .fullPage))
        #expect(full.image.width == 800 && full.image.height == 1600)
        #expect(try rgb(full.image) == [255, 34, 0])
        #expect(try rgb(full.image, y: 1500) == [17, 34, 51])
        #expect(full.source == "127.0.0.1")
    }

    @Test func visibleAreaUsesTheURLAnchorAndFullPageStartsAtTheTop() async throws {
        let listener = try LoopbackWebpage()
        defer { listener.stop() }
        let address = try await listener.start() + "#footer"
        let service = URLCaptureService()
        let visible = try await service.capture(URLCaptureRequest(address: address, width: 800, height: 600,
                                                                   appearance: .light, scope: .viewport))
        #expect(try rgb(visible.image, y: 500) == [17, 34, 51])

        let full = try await service.capture(URLCaptureRequest(address: address, width: 800, height: 600,
                                                                appearance: .light, scope: .fullPage))
        #expect(try rgb(full.image) == [255, 34, 0])
        #expect(try rgb(full.image, y: 1500) == [17, 34, 51])
    }

    @Test func browserCookiesAreDiscardedBetweenCaptures() async throws {
        let listener = try LoopbackWebpage(page: """
            <!doctype html>
            <body><script>
            document.body.style.background = document.cookie.includes('seen=1') ? '#f00' : '#0c0';
            document.cookie = 'seen=1; Max-Age=3600; Path=/';
            </script></body>
            """)
        defer { listener.stop() }
        let address = try await listener.start()
        let service = URLCaptureService()
        let request = try URLCaptureRequest(address: address, width: 390, height: 500,
                                            appearance: .light, scope: .viewport)
        for _ in 0..<2 {
            let capture = try await service.capture(request)
            #expect(try rgb(capture.image) == [0, 204, 0])
        }
    }

    @Test(.timeLimit(.minutes(1))) func captureContinuesWhenAWebpageImageStalls() async throws {
        let listener = try LoopbackWebpage(page: """
            <!doctype html>
            <style>html, body { margin: 0; background: #123; }</style>
            <img src="/stall.png" width="1" height="1">
            """, stalledPath: "/stall.png")
        defer { listener.stop() }
        let address = try await listener.start()
        let capture = try await URLCaptureService().capture(URLCaptureRequest(address: address, width: 390,
            height: 500, appearance: .light, scope: .viewport))
        #expect(try rgb(capture.image) == [17, 34, 51])
    }

    @Test(.timeLimit(.minutes(1))) func fullPageRendersContentRevealedWhenScrolledIntoView() async throws {
        let listener = try LoopbackWebpage(page: """
            <!doctype html>
            <style>body { margin: 0; } main { height: 1900px; }
            footer { height: 350px; background: #c00; }</style>
            <main>Top of page</main>
            <footer>Deferred content</footer>
            <script>
            const footer = document.querySelector('footer');
            new IntersectionObserver(entries => {
                if (entries.some(entry => entry.isIntersecting)) footer.style.background = '#0c0';
            }).observe(footer);
            </script>
            """)
        defer { listener.stop() }
        let address = try await listener.start()
        let image = try await URLCaptureService().capture(URLCaptureRequest(address: address, width: 800,
            height: 600, appearance: .light, scope: .fullPage)).image
        #expect(image.height == 2250)
        let footer = try rgb(image, y: 2050)
        #expect(footer == [0, 204, 0])
    }

    private func rgb(_ image: CGImage, y: Int = 50) throws -> [UInt8] {
        let cropped = try #require(image.cropping(to: CGRect(x: 50, y: y, width: 1, height: 1)))
        var bytes = [UInt8](repeating: 0, count: 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
            let context = try #require(CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                                 bytesPerRow: 4, space: colorSpace,
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return Array(bytes.prefix(3))
    }
}

private struct LoopbackWebpage {
    private let listener: NWListener
    private let page: String
    private let stalledPath: String?
    private let queue = DispatchQueue(label: "SuperShotTests.Webpage")
    private static let html = """
        <!doctype html>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          html, body { margin: 0; background: #f20; }
          main { height: 1400px; }
          footer { height: 200px; background: #123; }
          @media (prefers-color-scheme: dark) { html, body { background: #07d; } }
          @media (max-width: 500px) and (prefers-color-scheme: dark) { html, body { background: #0f7; } }
        </style>
        <main>Test page</main>
        <footer id="footer">Below the fold</footer>
        """

    init(page: String? = nil, stalledPath: String? = nil) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        self.page = page ?? Self.html
        self.stalledPath = stalledPath
    }

    func start() async throws -> String {
        let queue = self.queue
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
                guard let data else { connection.cancel(); return }
                if let stalledPath, String(decoding: data, as: UTF8.self).hasPrefix("GET \(stalledPath) ") {
                    queue.asyncAfter(deadline: .now() + 40) { connection.cancel() }
                    return
                }
                let body = page
                let header = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n"
                    + "Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n"
                connection.send(content: Data((header + body).utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
        let listener = self.listener
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    if let port = listener.port {
                        continuation.resume(returning: "http://127.0.0.1:\(port.rawValue)/")
                    } else {
                        continuation.resume(throwing: NWError.posix(.EADDRNOTAVAIL))
                    }
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() { listener.cancel() }
}
