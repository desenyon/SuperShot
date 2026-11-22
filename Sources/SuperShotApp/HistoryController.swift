import AppKit
import SwiftUI
import Observation
import Library
import Document
import Render
import DesignSystem

@MainActor @Observable final class HistoryModel {
    let store: HistoryStore
    var entries: [HistoryEntry] = []
    var collections: [String] = []
    var query = ""
    var presentation = 0
    var error: String?
    var open: ((CaptureDocument) -> Void)?
    var copyEntry: ((UUID) async throws -> Void)?
    var capture: (() -> Void)?
    var openSettings: (() -> Void)?
    var openRecordings: (() -> Void)?
    var historyEnabled: () -> Bool = { true }
    var isLoading = false
    private var searchTask: Task<Void, Never>?
    init(store: HistoryStore) { self.store = store }
    func search() {
        searchTask?.cancel()
        let query = query
        isLoading = true
        searchTask = Task {
            do {
                let found = try await store.all(query: query)
                let names = try await store.collectionNames()
                guard !Task.isCancelled else { return }
                entries = found
                collections = names
                isLoading = false
            } catch {
                guard !Task.isCancelled else { return }
                isLoading = false
                self.error = error.localizedDescription
            }
        }
    }
    func openEntry(_ entry: HistoryEntry) {
        Task { do { open?(try await store.document(entry.id)) } catch { self.error = error.localizedDescription } }
    }
    func delete(_ entry: HistoryEntry) {
        Task { do { try await store.remove(entry.id); search() } catch { self.error = error.localizedDescription } }
    }
    func update(_ metadata: HistoryMetadata, for entry: HistoryEntry) async -> Bool {
        do {
            guard let updated = try await store.updateMetadata(metadata, id: entry.id) else {
                search()
                error = "This capture is no longer in the library."
                return false
            }
            if let index = entries.firstIndex(where: { $0.id == entry.id }) { entries[index] = updated }
            search()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
    /// Copies the full-resolution capture with its edits, not the small library thumbnail.
    func copy(_ entry: HistoryEntry) {
        Task {
            do {
                if let copyEntry { try await copyEntry(entry.id); return }
                let document = try await store.document(entry.id)
                let image = try await Task.detached(priority: .userInitiated) { try DocumentRenderer.render(document) }.value
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([NSImage(cgImage: image, size: .zero)])
            } catch { self.error = error.localizedDescription }
        }
    }
}

@MainActor final class HistoryController: NSWindowController {
    let model: HistoryModel
    init(store: HistoryStore, open: @escaping (CaptureDocument) -> Void, capture: (() -> Void)? = nil,
         openSettings: (() -> Void)? = nil, openRecordings: (() -> Void)? = nil, historyEnabled: @escaping () -> Bool = { true },
         copyEntry: ((UUID) async throws -> Void)? = nil) {
        model = HistoryModel(store: store)
        model.open = open
        model.openSettings = openSettings
        model.openRecordings = openRecordings
        model.copyEntry = copyEntry
        model.historyEnabled = historyEnabled
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: DS.previewSize),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Library"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false; window.minSize = CGSize(width: 620, height: 420)
        if let capture {
            model.capture = { [weak window] in
                window?.orderOut(nil)
                capture()
            }
        }
        let host = NSHostingView(rootView: HistoryView(model: model)); host.sizingOptions = []
        window.contentView = host; window.setContentSize(DS.previewSize); window.center()
        super.init(window: window)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func present() {
        if window?.isVisible != true { model.presentation &+= 1 }
        model.search()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
    func refreshIfVisible() {
        if window?.isVisible == true { model.search() }
    }
}
