import AppKit
import SwiftUI
import Observation
import DesignSystem
import Export

@MainActor final class ReviewLinksController: NSObject, NSWindowDelegate {
    private var window: NSPanel?
    private var activeModel: ReviewLinksModel?

    func show(image: CGImage, title: String, parent: NSWindow? = nil) {
        present(asset: .image(image), title: title, parent: parent)
    }

    func show(file: URL, title: String, parent: NSWindow? = nil) {
        present(asset: .file(ReviewLinkFile(url: file)), title: title, parent: parent)
    }

    func showManagement(parent: NSWindow? = nil) {
        present(asset: nil, title: "", parent: parent)
    }

    static func preview(image: CGImage) -> some View {
        let configuration = ReviewLinksConfiguration(address: "https://reviews.example.com", uploadKey: String(repeating: "p", count: 32), receipts: [])
        return ReviewLinksView(model: ReviewLinksModel(asset: .image(image), title: "Design review", preview: configuration), close: {})
    }

    private func present(asset: ReviewLinkAsset?, title: String, parent: NSWindow?) {
        if activeModel?.busy == true {
            window?.makeKeyAndOrderFront(nil)
            return
        }
        window?.close()
        let size = CGSize(width: 460, height: asset == nil ? 420 : 570)
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable],
                            backing: .buffered, defer: false)
        panel.title = asset == nil ? "Review Links" : "Create Review Link"
        panel.contentMinSize = CGSize(width: 360, height: 360)
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self
        let model = ReviewLinksModel(asset: asset, title: title)
        activeModel = model
        let host = NSHostingView(rootView: ReviewLinksView(model: model, close: { [weak panel] in panel?.close() }))
        host.sizingOptions = []
        panel.contentView = host
        panel.setContentSize(size)
        if let parent { panel.setFrameTopLeftPoint(CGPoint(x: parent.frame.midX - size.width / 2, y: parent.frame.maxY - DS.xl)) }
        else { panel.center() }
        window = panel
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        DS.Motion.present(panel, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { activeModel?.busy != true }
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        activeModel = nil
        window = nil
    }
}

/// Owns the flattened temporary file prepared by the recording editor.
private final class ReviewLinkFile: Sendable {
    let url: URL
    init(url: URL) { self.url = url }
    deinit { try? FileManager.default.removeItem(at: url) }
}

private enum ReviewLinkAsset: Sendable {
    case image(CGImage)
    case file(ReviewLinkFile)

    var label: String {
        switch self {
        case .image: "Flattened screenshot"
        case .file(let file): file.url.pathExtension.lowercased() == "png" ? "Exported screenshot" : "Exported recording"
        }
    }

    func encoded() throws -> (Data, String) {
        switch self {
        case .image(let image):
            return (try ImageExport.encode(image), "image/png")
        case .file(let file):
            let url = file.url
            let mime: String
            switch url.pathExtension.lowercased() {
            case "png": mime = "image/png"
            case "mp4": mime = "video/mp4"
            case "mov": mime = "video/quicktime"
            default: throw ReviewLinksError.asset
            }
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true, let size = values.fileSize else { throw ReviewLinksError.asset }
            guard size <= ReviewLinksClient.mediaLimit else { throw ReviewLinksError.size }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            guard let data = try handle.read(upToCount: ReviewLinksClient.mediaLimit + 1), !data.isEmpty else {
                throw ReviewLinksError.asset
            }
            guard data.count <= ReviewLinksClient.mediaLimit else { throw ReviewLinksError.size }
            return (data, mime)
        }
    }
}

@MainActor @Observable private final class ReviewLinksModel {
    let asset: ReviewLinkAsset?
    var title: String
    var address = ""
    var uploadKey = ""
    var receipts: [ReviewLinkReceipt] = []
    var result: ReviewLinkReceipt?
    var error: String?
    var busy = false
    var managing: Bool
    var editingConnection = true

    private let client = ReviewLinksClient()
    private var pending: ReviewLinkReceipt?

    init(asset: ReviewLinkAsset?, title: String, preview: ReviewLinksConfiguration? = nil) {
        self.asset = asset
        self.title = Self.limitedTitle(title)
        managing = asset == nil
        do {
            let configuration = try preview ?? ReviewLinksStore.load()
            address = configuration.address
            uploadKey = configuration.uploadKey
            receipts = configuration.receipts
            editingConnection = destination == nil || uploadKey.isEmpty
        } catch {
            self.error = "Saved review links could not be read. \(error.localizedDescription)"
        }
    }

    var destination: String? {
        (try? ReviewLinksEndpoint(address))?.url.absoluteString
    }

    private static func limitedTitle(_ title: String) -> String {
        String(String.UnicodeScalarView(title.unicodeScalars.prefix(160)))
    }

    func upload() async {
        guard let asset, !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let endpoint = try ReviewLinksEndpoint(address)
            let key = uploadKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard key.utf8.count >= 32, key.unicodeScalars.allSatisfy({ 33...126 ~= $0.value }) else {
                throw ReviewLinksError.uploadKey
            }
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = trimmedTitle.isEmpty ? "Capture" : Self.limitedTitle(trimmedTitle)
            let payload = try await Task.detached(priority: .userInitiated) { try asset.encoded() }.value
            guard payload.0.count <= ReviewLinksClient.mediaLimit else { throw ReviewLinksError.size }
            let receipt: ReviewLinkReceipt
            if let pending, pending.server == endpoint.url.absoluteString, pending.title == name { receipt = pending }
            else { receipt = ReviewLinkReceipt(server: endpoint, title: name) }
            try ReviewLinksStore.update {
                $0.address = endpoint.url.absoluteString
                $0.uploadKey = key
                if !$0.receipts.contains(where: { $0.id == receipt.id }) { $0.receipts.insert(receipt, at: 0) }
            }
            pending = receipt
            receipts = try ReviewLinksStore.load().receipts
            try await client.create(receipt, key: key, data: payload.0, mime: payload.1)
            var uploaded = receipt
            uploaded.uploaded = true
            result = uploaded
            pending = nil
            try ReviewLinksStore.update { configuration in
                guard let index = configuration.receipts.firstIndex(where: { $0.id == uploaded.id }) else { return }
                configuration.receipts[index] = uploaded
            }
            receipts = try ReviewLinksStore.load().receipts
        } catch {
            self.error = error.localizedDescription
        }
    }

    func revoke(_ receipt: ReviewLinkReceipt) async {
        guard !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await client.revoke(receipt)
            try ReviewLinksStore.update { $0.receipts.removeAll { $0.id == receipt.id } }
            receipts = try ReviewLinksStore.load().receipts
            if result?.id == receipt.id { result = nil }
            if pending?.id == receipt.id { pending = nil }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct ReviewLinksView: View {
    @Bindable var model: ReviewLinksModel
    let close: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @LocalState private var confirming: ReviewLinkReceipt?
    @LocalState private var copied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.lg) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.lg) {
                    if model.managing { management }
                    else if let result = model.result { shared(result) }
                    else if let asset = model.asset { form(asset) }
                    if let error = model.error {
                        Label { Text(error).textSelection(.enabled) } icon: { Icon("warning", size: DS.iconSize) }
                            .font(DS.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .padding(DS.xl)
        .background { WorkspaceBackground() }
        .animation(DS.Motion.panel(reduceMotion), value: model.managing)
        .animation(DS.Motion.panel(reduceMotion), value: model.result?.id)
        .confirmationDialog("Revoke this review link?", isPresented: Binding(
            get: { confirming != nil }, set: { if !$0 { confirming = nil } }
        ), titleVisibility: .visible, presenting: confirming) { receipt in
            Button("Revoke Link", role: .destructive) { Task { await model.revoke(receipt) } }
        } message: { _ in
            Text("The server will remove the uploaded capture and its feedback. Copies already downloaded can still exist.")
        }
    }

    private func form(_ asset: ReviewLinkAsset) -> some View {
        VStack(alignment: .leading, spacing: DS.md) {
            assetPreview(asset)
            field("Title", placeholder: "Capture title", text: $model.title)
            Hairline()
            if !model.editingConnection, let destination = model.destination {
                HStack(spacing: DS.sm) {
                    Icon("globe", size: DS.iconSize)
                    Text(destination).font(DS.body).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Change…") { model.editingConnection = true }.buttonStyle(QuietButtonStyle())
                }
            } else {
                field("Review server", placeholder: "https://reviews.example.com", text: $model.address)
                if !model.address.isEmpty && model.destination == nil {
                    Text("Enter the HTTPS address with no path.").font(DS.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: DS.xs) {
                    Text("Upload key").font(DS.caption)
                    SecureField("Key from your review server", text: $model.uploadKey)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Upload key")
                }
            }
            Text("Anyone with the link can view the upload and leave guest feedback. Uploading sends this rendered file to the server above.")
                .font(DS.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .disabled(model.busy)
    }

    @ViewBuilder private func assetPreview(_ asset: ReviewLinkAsset) -> some View {
        switch asset {
        case .image(let image):
            VStack(alignment: .leading, spacing: DS.sm) {
                Image(decorative: image, scale: 1)
                    .resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 200)
                    .background(DS.card(scheme))
                    .clipShape(RoundedRectangle(cornerRadius: DS.smallRadius))
                    .accessibilityHidden(true)
                Text(asset.label).font(DS.caption).foregroundStyle(.secondary)
            }
            case .file(let file):
                let url = file.url
            HStack(spacing: DS.sm) {
                Icon(url.pathExtension.lowercased() == "png" ? "image" : "play", size: DS.iconSize)
                VStack(alignment: .leading, spacing: DS.xs) {
                    Text(url.lastPathComponent).font(DS.emphasis).lineLimit(1).truncationMode(.middle)
                    Text(asset.label).font(DS.caption).foregroundStyle(.secondary)
                }
            }.padding(DS.md).frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.card(scheme), in: RoundedRectangle(cornerRadius: DS.smallRadius))
        }
    }

    private func field(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: DS.xs) {
            Text(label).font(DS.caption)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder).accessibilityLabel(label)
        }
    }

    private func shared(_ receipt: ReviewLinkReceipt) -> some View {
        VStack(alignment: .leading, spacing: DS.md) {
            Text("Review link ready").font(DS.title)
            Text(receipt.title).font(DS.emphasis)
            if let url = receipt.publicURL {
                Text(url.absoluteString).font(DS.mono).textSelection(.enabled)
                HStack(spacing: DS.sm) {
                    copyLink(receipt, url: url, primary: true)
                    Button("Open in Browser") { NSWorkspace.shared.open(url) }.buttonStyle(QuietButtonStyle())
                }
            }
        }
    }

    private var management: some View {
        VStack(alignment: .leading, spacing: DS.md) {
            Text("Review links").font(DS.title)
            if model.receipts.isEmpty {
                Text("Links you create on this Mac appear here.").font(DS.body).foregroundStyle(.secondary)
            }
            ForEach(model.receipts) { receipt in
                VStack(alignment: .leading, spacing: DS.sm) {
                    Text(receipt.title).font(DS.emphasis)
                    Text(receipt.uploaded ? receipt.server : "Upload unconfirmed · \(receipt.server)")
                        .font(DS.caption).foregroundStyle(.secondary).lineLimit(2)
                    HStack(spacing: DS.sm) {
                        if receipt.uploaded, let url = receipt.publicURL {
                            copyLink(receipt, url: url, primary: false)
                            Button("Open") { NSWorkspace.shared.open(url) }.buttonStyle(QuietButtonStyle())
                        }
                        Spacer()
                        Button("Revoke…", role: .destructive) { confirming = receipt }.buttonStyle(QuietButtonStyle())
                    }
                }.padding(DS.md).frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.card(scheme), in: RoundedRectangle(cornerRadius: DS.smallRadius))
            }
        }
        .disabled(model.busy)
    }

    @ViewBuilder private func copyLink(_ receipt: ReviewLinkReceipt, url: URL, primary: Bool) -> some View {
        let label = copied == receipt.id ? "Copied" : "Copy Link"
        let action = {
            NSPasteboard.general.clearContents()
            if NSPasteboard.general.setString(url.absoluteString, forType: .string) { copied = receipt.id }
            else { model.error = "The review link could not be copied." }
        }
        if primary { Button(label, action: action).buttonStyle(PrimaryButtonStyle()) }
        else { Button(label, action: action).buttonStyle(QuietButtonStyle()) }
    }

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.sm) {
                navigation.fixedSize()
                Spacer(minLength: DS.sm)
                footerActions.fixedSize()
            }
            VStack(alignment: .trailing, spacing: DS.sm) {
                HStack { navigation; Spacer() }
                footerActions
            }
        }
    }

    @ViewBuilder private var navigation: some View {
        if model.asset != nil {
            Button(model.managing ? "Back" : "Manage Links") {
                model.managing.toggle()
            }.buttonStyle(QuietButtonStyle()).disabled(model.busy)
        }
    }

    private var footerActions: some View {
        HStack(spacing: DS.sm) {
            if model.busy {
                ProgressView().controlSize(.small).accessibilityLabel("Contacting review server")
            }
            if !model.managing && model.result == nil {
                Button("Cancel", action: close).buttonStyle(QuietButtonStyle()).disabled(model.busy)
                Button("Upload and Create Link") { Task { await model.upload() } }
                    .buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                    .disabled(model.busy || model.destination == nil || model.uploadKey.isEmpty)
            } else {
                Button("Done", action: close).buttonStyle(QuietButtonStyle()).keyboardShortcut(.defaultAction)
                    .disabled(model.busy)
            }
        }
    }
}
