import AppKit
import DesignSystem
import Foundation
import Observation
import SwiftUI

struct PublishedRelease: Decodable, Sendable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name", name, body, htmlURL = "html_url"
    }

    func isNewer(than installed: String) -> Bool {
        let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        return version.compare(installed, options: [.numeric]) == .orderedDescending
    }
}

@MainActor @Observable final class ReleaseNotesController {
    private var window: NSWindow?
    private var request: Task<Void, Never>?
    private(set) var release: PublishedRelease?
    private(set) var failure: String?
    let installedVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.1"
    static let page = URL(string: "https://github.com/desenyon/SuperShot/releases")!

    static func preview() -> some View {
        let controller = ReleaseNotesController()
        controller.release = PublishedRelease(tagName: "v0.1.1", name: "SuperShot 0.1.1",
            body: "Updated screenshot controls, easier pin unlocking, and improvements to Ask.",
            htmlURL: page)
        return ReleaseNotesView(controller: controller)
    }

    func present() {
        if window == nil {
            let host = NSHostingController(rootView: ReleaseNotesView(controller: self))
            let newWindow = NSWindow(contentViewController: host)
            newWindow.title = "SuperShot Updates"
            newWindow.styleMask = [.titled, .closable, .resizable]
            newWindow.isReleasedWhenClosed = false
            newWindow.setContentSize(CGSize(width: 540, height: 480))
            newWindow.center()
            window = newWindow
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        refresh()
    }

    func refresh() {
        request?.cancel()
        release = nil
        failure = nil
        request = Task {
            do {
                let endpoint = URL(string: "https://api.github.com/repos/desenyon/SuperShot/releases/latest")!
                var query = URLRequest(url: endpoint, timeoutInterval: 15)
                query.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: query)
                guard !Task.isCancelled else { return }
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                release = try JSONDecoder().decode(PublishedRelease.self, from: data)
            } catch {
                if !Task.isCancelled { failure = "Couldn’t check for updates. Try again or view releases on GitHub." }
            }
        }
    }
}

private struct ReleaseNotesView: View {
    let controller: ReleaseNotesController

    var body: some View {
        VStack(alignment: .leading, spacing: DS.md) {
            WorkspaceHeader(title: "SuperShot Updates", icon: "arrow-clockwise")
            if let release = controller.release {
                Text(release.isNewer(than: controller.installedVersion) ? "Version \(release.tagName) is available" : "You’re up to date")
                    .font(DS.emphasis)
                Text("Installed version \(controller.installedVersion)").font(DS.caption).foregroundStyle(.secondary)
                Hairline()
                ScrollView {
                    Text(release.body ?? "Release details are available on GitHub.")
                        .font(DS.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if let failure = controller.failure {
                Text(failure).foregroundStyle(.secondary)
                Button("Try again", action: controller.refresh).buttonStyle(QuietButtonStyle())
                Spacer()
            } else {
                ProgressView("Checking GitHub…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Link("View GitHub releases", destination: ReleaseNotesController.page)
        }
        .padding(DS.xl)
        .background { WorkspaceBackground() }
    }
}
