import Foundation
import Testing
@testable import SuperShotApp

struct CaptureURLTests {
    @Test(arguments: CaptureURLMode.allCases)
    func captureModesReachTheirCommands(mode: CaptureURLMode) throws {
        let url = try #require(URL(string: "supershot://capture?mode=\(mode.rawValue)"))
        #expect(CaptureURLCommand(url) == .capture(mode))
    }

    @Test func recordingAndLibraryCommands() throws {
        #expect(CaptureURLCommand(try #require(URL(string: "supershot://record"))) == .record)
        #expect(CaptureURLCommand(try #require(URL(string: "supershot://recordings"))) == .recordings)
        #expect(CaptureURLCommand(try #require(URL(string: "supershot://history"))) == .history)
        #expect(CaptureURLCommand(try #require(URL(string: "supershot://recent"))) == .recent)
    }

    @Test func onlySupportedAreaDelaysLaunchCapture() throws {
        #expect(CaptureURLCommand(try #require(URL(string: "supershot://capture"))) == .capture(.area))
        #expect(CaptureURLCommand(try #require(URL(string: "supershot://capture?mode=area&delay=5"))) == .timed(5))
        for value in ["supershot://capture?mode=window&delay=5", "supershot://capture?mode=area&delay=99",
                      "supershot://capture?mode=unknown", "https://capture?mode=area"] {
            #expect(CaptureURLCommand(try #require(URL(string: value))) == nil)
        }
    }
}
