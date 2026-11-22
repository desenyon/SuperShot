import AppKit
import SwiftUI
import Library
import DesignSystem

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
    @LocalState private var editing: HistoryEntry?
    @LocalState private var period = HistoryPeriod.all
    @LocalState private var collection: String?
    @LocalState private var showsReminders = false
    @LocalState private var selectedID: UUID?
    @FocusState private var searchFocused: Bool

    init(model: HistoryModel, initialSelection: UUID? = nil) {
        self.model = model
        _selectedID = LocalState(wrappedValue: initialSelection)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            workspace(at: timeline.date)
        }
        .background { WorkspaceBackground() }
        .ignoresSafeArea()
        .onChange(of: model.query) { _, _ in model.search() }
        .onChange(of: model.entries.map(\.id)) { _, ids in
            if let selectedID, !ids.contains(selectedID) { self.selectedID = nil }
        }
        .onChange(of: model.collections) { _, names in
            if let collection, !names.contains(where: { matchesCollection($0, collection) }) { self.collection = nil }
        }
        .onExitCommand {
            if editing == nil { selectedID = nil }
        }
        .sheet(item: $editing) { entry in
            HistoryMetadataSheet(entry: entry, collections: model.collections) { metadata in
                if await model.update(metadata, for: entry) { editing = nil }
            }
        }
        .confirmationDialog("Delete this capture from the library?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) { if let deleting { model.delete(deleting) }; deleting = nil }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { Text("Files you exported are kept.") }
        .alert("Library", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private func workspace(at now: Date) -> some View {
        let entries = filteredEntries(at: now)
        let selection = entries.first { $0.id == selectedID }
        return VStack(spacing: 0) {
            header
            filters(entries: entries, now: now)
            Hairline()
            GeometryReader { geometry in
                if let selection {
                    if geometry.size.width >= DS.previewSize.width - DS.sidebarWidth {
                        HStack(spacing: 0) {
                            gallery(entries, now: now)
                            Divider()
                            inspector(selection, now: now).frame(width: DS.sidePanelWidth + DS.xl)
                        }
                    } else {
                        inspector(selection, now: now)
                    }
                } else {
                    gallery(entries, now: now)
                }
            }
        }
        .animation(DS.Motion.panel(reduceMotion), value: selection?.id)
        .animation(DS.Motion.gentle(reduceMotion), value: entries.map(\.id))
    }

    private var header: some View {
        HStack(spacing: DS.xl) {
            WorkspaceHeader(title: "Library", icon: "images")
            if let openRecordings = model.openRecordings {
                Button("Recordings", action: openRecordings).buttonStyle(QuietButtonStyle())
            }
            Spacer(minLength: 0)
            HStack(spacing: DS.sm) {
                IconButton("magnifying-glass", label: "Focus library search", size: DS.xl) { searchFocused = true }
                    .keyboardShortcut("f", modifiers: .command)
                TextField("Search captures", text: $model.query)
                    .textFieldStyle(.plain).font(DS.body).focused($searchFocused)
                    .accessibilityLabel("Search capture names, tags, notes, recognized text, and Ask")
                if !model.query.isEmpty {
                    IconButton("x-circle", label: "Clear search", size: DS.xl) { model.query = "" }
                }
            }
            .padding(.horizontal, DS.md).frame(maxWidth: DS.historySearchWidth + DS.xxl * 2)
            .frame(height: DS.toolButtonSize)
            .background(DS.card(scheme), in: RoundedRectangle(cornerRadius: DS.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: DS.controlRadius)
                .strokeBorder(searchFocused ? DS.accent : DS.hairline(scheme)).allowsHitTesting(false))
            if !model.entries.isEmpty, let capture = model.capture {
                Button(action: capture) {
                    HStack(spacing: DS.xs) { Icon("frame-corners"); Text("Capture an area") }
                }.buttonStyle(QuietButtonStyle())
            }
        }
        .padding(.horizontal, DS.xl).padding(.top, DS.windowHeaderInset).padding(.bottom, DS.lg)
    }

    private func filters(entries: [HistoryEntry], now: Date) -> some View {
        let due = model.entries.compactMap { $0.metadata?.reminder }.filter { $0 <= now }.count
        return HStack(spacing: DS.md) {
            SegmentedChoice(HistoryPeriod.allCases.map { ($0, $0.rawValue, nil) }, selection: period) {
                period = $0; showsReminders = false; selectedID = nil
            }
            .frame(width: DS.historyFilterWidth).accessibilityLabel("Capture date")
            if !model.collections.isEmpty {
                Menu {
                    Button("All folders") { collection = nil; selectedID = nil }
                    ForEach(model.collections, id: \.self) { name in
                        Button(name) { collection = name; selectedID = nil }
                    }
                } label: {
                    HStack(spacing: DS.xs) {
                        Icon("folder")
                        Text(collection ?? "Folders").lineLimit(1)
                    }
                    .frame(maxWidth: DS.pinPopoverWidth, alignment: .leading)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Filter by folder")
                .accessibilityValue(collection ?? "All folders")
            }
            Button {
                showsReminders.toggle(); period = .all; selectedID = nil
            } label: {
                HStack(spacing: DS.xs) {
                    Icon("clock")
                    Text(due > 0 ? "Reminders (\(due))" : "Reminders")
                }
            }
            .buttonStyle(QuietButtonStyle())
            .foregroundStyle(showsReminders ? DS.actionInk(scheme) : Color.primary)
            .accessibilityAddTraits(showsReminders ? .isSelected : [])
            Spacer(minLength: DS.sm)
            Text(entries.count == 1 ? "1 capture" : "\(entries.count) captures")
                .font(DS.caption).foregroundStyle(.secondary).lineLimit(1).fixedSize()
        }
        .padding(.horizontal, DS.xl).padding(.bottom, DS.md)
    }

    private func filteredEntries(at now: Date) -> [HistoryEntry] {
        model.entries.filter { entry in
            let inCollection = collection.map { matchesCollection(entry.metadata?.collection ?? "", $0) } ?? true
            return inCollection && (showsReminders ? entry.metadata?.reminder != nil
                                    : period.includes(entry.date, now: now, calendar: .current))
        }
    }

    private func matchesCollection(_ name: String, _ selected: String) -> Bool {
        name.compare(selected, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    @ViewBuilder private func gallery(_ entries: [HistoryEntry], now: Date) -> some View {
        if entries.isEmpty {
            emptyState.frame(maxWidth: .infinity, maxHeight: .infinity).transition(.opacity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.xl) {
                    if showsReminders {
                        let sorted = entries.sorted { ($0.metadata?.reminder ?? .distantFuture) < ($1.metadata?.reminder ?? .distantFuture) }
                        let due = sorted.filter { ($0.metadata?.reminder ?? .distantFuture) <= now }
                        let upcoming = sorted.filter { ($0.metadata?.reminder ?? .distantPast) > now }
                        if !due.isEmpty { section("Due", entries: due, now: now) }
                        if !upcoming.isEmpty { section("Upcoming", entries: upcoming, now: now) }
                    } else {
                        let calendar = Calendar.current
                        let days = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
                        ForEach(days.keys.sorted(by: >), id: \.self) { day in
                            let label = calendar.isDate(day, inSameDayAs: now) ? "Today"
                                : day.formatted(.dateTime.month(.abbreviated).day().year())
                            section(label, entries: days[day] ?? [], now: now)
                        }
                    }
                }
                .padding(DS.xl).id(model.presentation)
            }
        }
    }

    private func section(_ title: String, entries: [HistoryEntry], now: Date) -> some View {
        let minimumWidth = selectedID == nil ? DS.historyCardWidth : DS.historyCardWidth - DS.xxl
        return VStack(alignment: .leading, spacing: DS.md) {
            Text(title).font(DS.emphasis).accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumWidth), spacing: DS.lg)], spacing: DS.lg) {
                ForEach(entries) { entry in
                    HistoryCard(entry: entry, url: model.store.thumbnailURL(entry.id), selected: entry.id == selectedID,
                                now: now, select: { selectedID = entry.id }, open: { model.openEntry(entry) },
                                copy: { model.copy(entry) }, delete: { deleting = entry })
                }
            }
        }
    }

    private func inspector(_ entry: HistoryEntry, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.sm) {
                Text("Details").font(DS.emphasis).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Edit details") { editing = entry }.buttonStyle(QuietButtonStyle())
                IconButton("x", label: "Close details") { selectedID = nil }
            }
            .padding(.horizontal, DS.lg).padding(.vertical, DS.sm)
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: DS.md) {
                    HistoryThumbnail(url: model.store.thumbnailURL(entry.id), updatedAt: entry.updatedAt)
                        .frame(height: DS.sidebarWidth - DS.xxl)
                        .clipShape(RoundedRectangle(cornerRadius: DS.smallRadius))
                    VStack(alignment: .leading, spacing: DS.xs) {
                        Text(entry.displayTitle).font(DS.title).textSelection(.enabled)
                        Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                            .font(DS.caption).foregroundStyle(.secondary)
                        Text("\(entry.width) × \(entry.height) px").font(DS.mono).foregroundStyle(.secondary)
                    }
                    if !entry.title.isEmpty, entry.title != entry.displayTitle { detailLine("Source", entry.title) }
                    if let collection = entry.metadata?.collection, !collection.isEmpty {
                        detailLine("Folder", collection)
                    }
                    if !entry.displayTags.isEmpty { detailLine("Tags", entry.displayTags.joined(separator: ", ")) }
                    if let summary = entry.displaySummary { detailLine("Summary", summary) }
                    if let notes = entry.metadata?.notes, !notes.isEmpty { detailLine("Notes", notes) }
                    if let reminder = entry.metadata?.reminder {
                        detailLine(reminder <= now ? "Reminder due" : "Reminder",
                                   reminder.formatted(date: .abbreviated, time: .shortened))
                        Button("Clear reminder") {
                            guard var metadata = entry.metadata else { return }
                            metadata.reminder = nil
                            Task { _ = await model.update(metadata, for: entry) }
                        }.buttonStyle(QuietButtonStyle())
                    }
                }
                .padding(DS.lg).frame(maxWidth: .infinity, alignment: .leading)
            }
            Hairline()
            HStack(spacing: DS.sm) {
                Button("Open in editor") { model.openEntry(entry) }
                    .buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.return, modifiers: .command)
                IconButton("copy", label: "Copy image") { model.copy(entry) }
                Spacer()
                IconButton("trash", label: "Delete capture") { deleting = entry }
            }
            .padding(.horizontal, DS.lg).padding(.vertical, DS.sm)
        }
        .modifier(GlassSurface(radius: DS.controlRadius))
    }

    private func detailLine(_ label: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: DS.xs) {
            Text(label).font(DS.emphasis).foregroundStyle(.secondary)
            Text(detail).font(DS.body).textSelection(.enabled)
        }
    }

    private var emptyState: some View {
        let searching = !model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let filtered = period != .all || collection != nil
        return VStack(spacing: DS.md) {
            if model.isLoading && model.entries.isEmpty {
                ProgressView().controlSize(.small).accessibilityLabel("Loading library")
            } else {
                let title = searching ? "No matching captures" : showsReminders ? "No reminders" : filtered ? "No captures in this view" : "No captures yet"
                let detail = searching ? "Try a name, tag, or word in the image." : showsReminders
                    ? "Open a capture’s details to set a reminder." : filtered
                    ? "Clear filters to see your other captures." : model.historyEnabled()
                    ? "Take an area screenshot to start your library." : "Turn on capture history to keep new screenshots here."
                Icon(searching ? "magnifying-glass" : showsReminders ? "clock" : "images", size: DS.xl)
                    .foregroundStyle(.secondary)
                Text(title).font(DS.title)
                Text(detail).font(DS.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if searching {
                    Button("Clear search") { model.query = "" }.buttonStyle(QuietButtonStyle())
                } else if showsReminders || filtered {
                    Button("Show all captures") { showsReminders = false; period = .all; collection = nil }
                        .buttonStyle(QuietButtonStyle())
                } else if !model.historyEnabled(), let openSettings = model.openSettings {
                    Button("Library Settings", action: openSettings).buttonStyle(PrimaryButtonStyle())
                } else if let capture = model.capture {
                    Button("Capture an area", action: capture).buttonStyle(PrimaryButtonStyle())
                }
            }
        }.padding(DS.xl)
    }
}

private struct HistoryCard: View {
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focused: Bool
    let entry: HistoryEntry
    let url: URL
    let selected: Bool
    let now: Date
    let select: () -> Void
    let open: () -> Void
    let copy: () -> Void
    let delete: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: DS.sm) {
                HistoryThumbnail(url: url, updatedAt: entry.updatedAt)
                    .aspectRatio(1.65, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: DS.smallRadius))
                VStack(alignment: .leading, spacing: DS.xs) {
                    Text(entry.displayTitle).font(DS.emphasis).lineLimit(1)
                    HStack(spacing: DS.xs) {
                        Text(entry.date.formatted(date: .omitted, time: .shortened))
                        if let reminder = entry.metadata?.reminder {
                            Spacer(minLength: DS.xs)
                            Icon("clock", size: DS.icon)
                            Text(reminder <= now ? "Due" : reminder.formatted(date: .abbreviated, time: .omitted))
                                .lineLimit(1)
                        }
                    }
                    .font(DS.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, DS.xs)
            }
            .padding(DS.xs).frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if selected { RoundedRectangle(cornerRadius: DS.groupRadius).fill(DS.accent.opacity(DS.subtleOpacity)) }
            }
            .overlay(RoundedRectangle(cornerRadius: DS.groupRadius)
                .strokeBorder(selected || focused ? DS.accent : .clear, lineWidth: DS.insetStroke))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focused)
        .focusEffectDisabled()
        .simultaneousGesture(TapGesture(count: 2).onEnded { open() })
        .accessibilityLabel(entry.displayTitle)
        .accessibilityHint("Show capture details")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .contextMenu {
            Button("Show details", action: select)
            Button("Open in editor", action: open)
            Button("Copy image", action: copy)
            Button("Delete…", role: .destructive, action: delete)
        }
    }
}

private struct HistoryThumbnail: View {
    private struct LoadKey: Equatable {
        let url: URL
        let updatedAt: Date?
    }

    @Environment(\.colorScheme) private var scheme
    @LocalState private var image: NSImage?
    let url: URL
    let updatedAt: Date?

    var body: some View {
        ZStack {
            DS.card(scheme)
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else { Icon("image", size: DS.xl).foregroundStyle(.secondary) }
        }
        .accessibilityHidden(true)
        .task(id: LoadKey(url: url, updatedAt: updatedAt)) {
            let data = await Task.detached { try? Data(contentsOf: url) }.value
            if !Task.isCancelled { image = data.flatMap(NSImage.init(data:)) }
        }
    }
}

private struct HistoryMetadataSheet: View {
    let entry: HistoryEntry
    let collections: [String]
    let save: (HistoryMetadata) async -> Void
    @Environment(\.dismiss) private var dismiss
    @LocalState private var draft: HistoryMetadata
    @LocalState private var tagText: String
    @LocalState private var saving = false

    init(entry: HistoryEntry, collections: [String], save: @escaping (HistoryMetadata) async -> Void) {
        self.entry = entry
        self.collections = collections
        self.save = save
        _draft = LocalState(wrappedValue: entry.metadata ?? HistoryMetadata())
        _tagText = LocalState(wrappedValue: entry.displayTags.joined(separator: ", "))
    }

    private var reminderEnabled: Binding<Bool> {
        Binding(get: { draft.reminder != nil }, set: { enabled in
            draft.reminder = enabled ? Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now : nil
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.md) {
            Text("Edit capture details").font(DS.title).padding(.horizontal, DS.xl).padding(.top, DS.lg)
            Form {
                TextField("Name", text: $draft.title, prompt: Text(entry.suggestions?.title ?? entry.title))
                HStack(spacing: DS.sm) {
                    TextField("Folder", text: $draft.collection)
                    if !collections.isEmpty {
                        Menu {
                            ForEach(collections, id: \.self) { name in
                                Button(name) { draft.collection = name }
                            }
                        } label: { Icon("folder-open") }
                        .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Choose an existing folder")
                    }
                }
                TextField("Tags", text: $tagText, prompt: Text("Separate with commas"))
                TextField("Summary", text: $draft.summary, prompt: Text(entry.suggestions?.summary ?? ""), axis: .vertical)
                    .lineLimit(1...3)
                TextField("Notes", text: $draft.notes, axis: .vertical).lineLimit(2...4)
                Toggle("Remind me in Library", isOn: reminderEnabled)
                if draft.reminder != nil {
                    DatePicker("Reminder", selection: Binding(get: { draft.reminder ?? .now }, set: { draft.reminder = $0 }))
                    Text("This capture stays in Library until you clear its reminder.").foregroundStyle(.secondary).font(DS.caption)
                }
            }
            .formStyle(.grouped)
            HStack(spacing: DS.sm) {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(QuietButtonStyle()).keyboardShortcut(.cancelAction)
                Button(saving ? "Saving…" : "Save") {
                    var metadata = draft
                    if tagText != entry.displayTags.joined(separator: ", ") {
                        metadata.tags = tagText.split(separator: ",", omittingEmptySubsequences: true).map(String.init)
                    }
                    saving = true
                    Task { await save(metadata); saving = false }
                }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            }.padding(.horizontal, DS.xl).padding(.bottom, DS.lg)
        }
        .frame(width: DS.welcomeSize.width, height: DS.settingsSize.height - DS.xxl)
        .disabled(saving).interactiveDismissDisabled(saving)
    }
}
