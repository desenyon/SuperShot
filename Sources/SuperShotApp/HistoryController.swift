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
    var presentation = 0
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
    func present() {
        if window?.isVisible != true { model.presentation &+= 1 }
        model.search()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

private enum HistoryPeriod: String, CaseIterable {
    case all = "All", today = "Today", week = "This week"
    func includes(_ date: Date, now: Date, calendar: Calendar) -> Bool {
        switch self {
        case .all: true
        case .today: calendar.isDate(date, inSameDayAs: now)
        case .week: calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear)
        }
    }
}

struct HistoryView: View {
    @Bindable var model: HistoryModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @LocalState private var deleting: HistoryEntry?
    @LocalState private var period = HistoryPeriod.all

    var body: some View {
        let now = Date()
        let entries = model.entries.filter { period.includes($0.date, now: now, calendar: .current) }
        VStack(spacing: 0) {
            header
            HStack {
                SegmentedChoice(HistoryPeriod.allCases.map { ($0, $0.rawValue, nil) }, selection: period) { period = $0 }
                    .frame(width: DS.historyFilterWidth).accessibilityLabel("Capture date")
                Spacer()
                Text(entries.count == 1 ? "1 capture" : "\(entries.count) captures")
                    .font(DS.mono).foregroundStyle(.secondary)
            }
            .padding(.horizontal, DS.xl).padding(.bottom, DS.md)
            Hairline()
            if entries.isEmpty {
                emptyState.frame(maxWidth: .infinity, maxHeight: .infinity).transition(.opacity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: DS.historyCardWidth), spacing: DS.lg)], spacing: DS.xl) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            HistoryCard(entry: entry, url: model.store.thumbnailURL(entry.id),
                                        open: { model.openEntry(entry) }, copy: { model.copy(entry) }, delete: { deleting = entry })
                                .staggeredAppear(index).transition(DS.Motion.rise(reduceMotion: reduceMotion))
                        }
                    }
                    .padding(DS.xl).id(model.presentation)
                }
            }
        }
        .animation(DS.Motion.gentle(reduceMotion), value: entries.map(\.id))
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
            Text("Library").font(DS.title)
            Spacer()
            HStack(spacing: DS.sm) {
                Icon("magnifying-glass", size: DS.icon).foregroundStyle(.secondary)
                TextField("Search apps or text in captures", text: $model.query).textFieldStyle(.plain).font(DS.body)
                if !model.query.isEmpty {
                    Button { model.query = "" } label: { Icon("xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.plain).help("Clear search")
                }
            }
            .padding(.horizontal, DS.md).frame(width: DS.historySearchWidth, height: DS.toolButtonSize)
            .background(DS.card(scheme), in: Capsule())
            .overlay(Capsule().strokeBorder(DS.hairline(scheme)))
        }
        .padding(.horizontal, DS.xl).padding(.top, DS.windowHeaderInset).padding(.bottom, DS.lg)
    }

    private var emptyState: some View {
        let searching = !model.query.isEmpty
        let filtered = period != .all
        return VStack(spacing: DS.md) {
            Icon(searching ? "magnifying-glass" : "images", size: DS.xl)
                .frame(width: DS.zoomLabelWidth, height: DS.zoomLabelWidth)
                .background(DS.card(scheme), in: RoundedRectangle(cornerRadius: DS.groupRadius))
            Text(searching ? "No matching captures" : filtered ? "No captures this period" : "No captures yet").font(DS.title)
            Text(searching ? "Try another app name or a word from the image."
                 : filtered ? "Choose All to see your earlier captures." : "Your screenshots appear here when capture history is enabled.")
                .font(DS.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if searching || filtered {
                Button(searching ? "Clear search" : "Show all captures") {
                    if searching { model.query = "" } else { period = .all }
                }.buttonStyle(QuietButtonStyle())
            }
        }.padding(DS.xl)
    }
}

private struct HistoryCard: View {
    @Environment(\.colorScheme) private var scheme
    @LocalState private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @LocalState private var image: NSImage?
    @LocalState private var appIcon: NSImage?
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
                    if let image { Image(nsImage: image).resizable().scaledToFit() }
                    else { Icon("photo", size: 26).foregroundStyle(.tertiary) }
                }
                .aspectRatio(1.65, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: DS.groupRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DS.groupRadius, style: .continuous).strokeBorder(hovering ? DS.accent : DS.hairline(scheme), lineWidth: hovering ? 1.5 : 1))
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
            HStack(spacing: DS.sm) {
                Group {
                    if let appIcon { Image(nsImage: appIcon).resizable().scaledToFit().saturation(0) }
                    else { Icon("app-window", size: DS.iconSize).foregroundStyle(.secondary) }
                }
                .frame(width: DS.metadataIconSize, height: DS.metadataIconSize).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.insetStroke) {
                    Text(entry.title).font(DS.emphasis).lineLimit(1)
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened)).font(DS.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: DS.xs)
                Text(verbatim: "\(entry.width) × \(entry.height)").font(DS.mono).foregroundStyle(.secondary)
            }
            .padding(.horizontal, DS.xs)
        }
        .contextMenu {
            Button("Open in editor", action: open)
            Button("Copy image", action: copy)
            Button("Delete…", role: .destructive, action: delete)
        }
        .hoverLift()
        .onHover { hovering = $0 }
        .animation(DS.Motion.hover(reduceMotion), value: hovering)
        .task(id: url) {
            appIcon = Self.sourceIcon(entry.title)
            let data = await Task.detached { try? Data(contentsOf: url) }.value
            if let data { image = NSImage(data: data) }
        }
    }

    private static func sourceIcon(_ title: String) -> NSImage? {
        guard !title.contains("/"), !title.isEmpty else { return nil }
        let workspace = NSWorkspace.shared
        let running = workspace.runningApplications.first { $0.localizedName == title }
        if let icon = running?.icon { return icon }
        // Older captures store the source's display name, without a bundle identifier.
        let directories = FileManager.default.urls(for: .applicationDirectory, in: .allDomainsMask)
        for directory in directories {
            for root in [directory, directory.appendingPathComponent("Utilities")] {
                let url = root.appendingPathComponent(title).appendingPathExtension("app")
                if FileManager.default.fileExists(atPath: url.path) { return workspace.icon(forFile: url.path) }
            }
        }
        return nil
    }
}
