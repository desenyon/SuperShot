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
    var query = ""
    var error: String?
    var open: ((CaptureDocument) -> Void)?
    private var searchTask: Task<Void, Never>?
    init(store: HistoryStore) { self.store = store }
    func search() {
        searchTask?.cancel()
        let query = query
        searchTask = Task {
            do {
                let found = try await store.all(query: query)
                guard !Task.isCancelled else { return }
                entries = found
            } catch { self.error = error.localizedDescription }
        }
    }
    func openEntry(_ entry: HistoryEntry) {
        Task { do { open?(try await store.document(entry.id)) } catch { self.error = error.localizedDescription } }
    }
    func delete(_ entry: HistoryEntry) {
        Task { do { try await store.remove(entry.id); search() } catch { self.error = error.localizedDescription } }
    }
    /// Copies the full-resolution capture with its edits, not the small library thumbnail.
    func copy(_ entry: HistoryEntry) {
        Task {
            do {
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
    init(store: HistoryStore, open: @escaping (CaptureDocument) -> Void) {
        model = HistoryModel(store: store); model.open = open
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: DS.previewSize),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Library"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false; window.minSize = CGSize(width: 620, height: 420)
        let host = NSHostingView(rootView: HistoryView(model: model)); host.sizingOptions = []
        window.contentView = host; window.setContentSize(DS.previewSize); window.center()
        super.init(window: window)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func present() { model.search(); NSApp.activate(ignoringOtherApps: true); showWindow(nil); window?.makeKeyAndOrderFront(nil) }
}

struct HistoryView: View {
    @Bindable var model: HistoryModel
    @Environment(\.colorScheme) private var scheme
    @LocalState private var deleting: HistoryEntry?

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            ScrollView {
                if model.entries.isEmpty { emptyState }
                else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210, maximum: 320), spacing: DS.lg)], spacing: DS.xl) {
                        ForEach(model.entries) { entry in
                            HistoryCard(entry: entry, url: model.store.thumbnailURL(entry.id),
                                        open: { model.openEntry(entry) }, copy: { model.copy(entry) }, delete: { deleting = entry })
                        }
                    }
                    .padding(DS.xl)
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(DS.background(scheme))
        .ignoresSafeArea()
        .onChange(of: model.query) { _, _ in model.search() }
        .confirmationDialog("Delete this capture from the library?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) { if let deleting { model.delete(deleting) }; deleting = nil }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { Text("Files you exported are not affected.") }
        .alert("Library", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private var header: some View {
        HStack(spacing: DS.md) {
            Text("Library").font(.system(size: 22, weight: .bold))
            Tag("\(model.entries.count)")
            Spacer()
            HStack(spacing: DS.sm) {
                Icon("magnifyingglass", size: 14).foregroundStyle(.secondary)
                TextField("Search by app, name, or text in the image", text: $model.query).textFieldStyle(.plain).font(DS.body)
                if !model.query.isEmpty {
                    Button { model.query = "" } label: { Icon("xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.plain).help("Clear search")
                }
            }
            .padding(.horizontal, DS.md).frame(width: 320, height: 32)
            .background(DS.card(scheme), in: Capsule())
            .overlay(Capsule().strokeBorder(DS.hairline(scheme)))
        }
        .padding(.horizontal, DS.xl).padding(.top, 44).padding(.bottom, DS.lg)
    }

    private var emptyState: some View {
        VStack(spacing: DS.md) {
            Icon(model.query.isEmpty ? "photo.stack" : "magnifyingglass", size: 41).foregroundStyle(.tertiary)
            Text(model.query.isEmpty ? "No captures yet" : "No matches").font(DS.title)
            Text(model.query.isEmpty ? "Everything you capture is kept here, and you can search for the words inside each image."
                 : "Nothing in your library matches “\(model.query)”.")
                .font(DS.body).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity).padding(.top, 120)
    }
}

private struct HistoryCard: View {
    @Environment(\.colorScheme) private var scheme
    @LocalState private var hovering = false
    @LocalState private var image: NSImage?
    let entry: HistoryEntry
    let url: URL
    let open: () -> Void
    let copy: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.sm) {
            Button(action: open) {
                ZStack {
                    DS.card(scheme)
                    if let image { Image(nsImage: image).resizable().scaledToFit().padding(DS.sm) }
                    else { Icon("photo", size: 26).foregroundStyle(.tertiary) }
                }
                .aspectRatio(1.5, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(hovering ? DS.accent : DS.hairline(scheme), lineWidth: hovering ? 1.5 : 1))
            }
            .buttonStyle(.plain).accessibilityLabel("Open \(entry.title)")
            .overlay(alignment: .topTrailing) {
                if hovering {
                    HStack(spacing: 2) {
                        IconButton("doc.on.doc", label: "Copy", size: 26, action: copy)
                        IconButton("trash", label: "Delete", size: 26, action: delete)
                    }
                    .padding(3).modifier(GlassSurface(radius: 10)).padding(DS.sm)
                    .transition(.opacity)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title).font(DS.emphasis).lineLimit(1)
                    Text(entry.date.formatted(.relative(presentation: .named))).font(DS.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(verbatim: "\(entry.width) × \(entry.height)").font(DS.mono).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, DS.xs)
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .task {
            let data = await Task.detached { try? Data(contentsOf: url) }.value
            if let data { image = NSImage(data: data) }
        }
    }
}
