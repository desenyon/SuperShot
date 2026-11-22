import Foundation
import Testing
@testable import Capture

struct URLCaptureTests {
    @Test func defaultsToSecureWebAddressAndUsesOnlyTheHostInHistory() throws {
        let request = try URLCaptureRequest(address: " example.org/path?private=value#anchor ", width: 1280, height: 800,
                                            appearance: .light, scope: .viewport)
        #expect(request.url.absoluteString == "https://example.org/path?private=value#anchor")
        #expect(request.source == "example.org")
        #expect(try URLCaptureRequest.parseAddress("example.org/?next=https://example.net").absoluteString ==
                "https://example.org/?next=https://example.net")
    }

    @Test(arguments: ["localhost:8080/demo", "127.0.0.1:8080/demo", "[::1]:8080/demo"])
    func treatsBareLoopbackAddressesAsLocalHTTP(_ address: String) throws {
        #expect(try URLCaptureRequest.parseAddress(address).absoluteString == "http://\(address)")
        #expect(try URLCaptureRequest.parseAddress("https://\(address)").absoluteString == "https://\(address)")
    }

    @Test(arguments: [
        "", "file:///etc/hosts", "javascript:alert(1)", "data:text/html,test", "https://",
        "https://user:password@example.org", "https://example.org:65536", "https://example.org\r\n",
        "https://example.org/some text", "https://example.org\\@elsewhere.org"
    ]) func rejectsInvalidOrPrivilegedNavigation(_ address: String) {
        #expect(throws: URLCaptureError.invalidAddress) {
            try URLCaptureRequest(address: address, width: 1280, height: 800, appearance: .light, scope: .viewport)
        }
    }

    @Test(arguments: [(127, 300), (300, 127), (4097, 600), (600, 4097), (0, 0)])
    func boundsViewportSize(_ size: (Int, Int)) {
        #expect(throws: URLCaptureError.invalidSize) {
            try URLCaptureRequest(address: "https://example.org", width: size.0, height: size.1,
                                  appearance: .dark, scope: .fullPage)
        }
    }

    @Test func fullPageKeepsTheRequestedBreakpointAndBoundsTheOutput() throws {
        let request = try URLCaptureRequest(address: "http://localhost:8010", width: 1200, height: 800,
                                            appearance: .dark, scope: .fullPage)
        #expect(try request.captureHeight(contentHeight: 2000.4) == 2001)
        #expect(try request.captureHeight(contentHeight: 300) == 800)
        #expect(throws: URLCaptureError.pageTooLarge) { try request.captureHeight(contentHeight: 40_000) }
        #expect(throws: URLCaptureError.pageTooLarge) { try request.captureHeight(contentHeight: .infinity) }
    }

    @Test func viewportIgnoresFullContentHeight() throws {
        let request = try URLCaptureRequest(address: "https://example.org", width: 390, height: 844,
                                            appearance: .dark, scope: .viewport)
        #expect(try request.captureHeight(contentHeight: 40_000) == 844)
    }

    @Test func devToolsEndpointMustBeLoopbackBrowserSocket() {
        #expect(URLCaptureService.devToolsEndpoint("43210\n/devtools/browser/55BE-41\n")?.absoluteString ==
                "ws://127.0.0.1:43210/devtools/browser/55BE-41")
        #expect(URLCaptureService.devToolsEndpoint("43210\nhttps://example.org") == nil)
        #expect(URLCaptureService.devToolsEndpoint("43210\n/devtools/browser/../page") == nil)
        #expect(URLCaptureService.devToolsEndpoint("43210\n/devtools/page/ABC") == nil)
        #expect(URLCaptureService.devToolsEndpoint("0\n/devtools/browser/ABC") == nil)
    }
}
