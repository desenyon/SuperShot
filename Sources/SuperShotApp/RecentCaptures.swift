import AppKit
import Capture
import DesignSystem
import Observation
import SwiftUI

@MainActor @Observable final class RecentCaptures {
    struct Entry: Identifiable {
        let capture: CapturedImage
        var disposable: Bool
        var id: UUID { capture.id }
        var cost: Int { capture.image.bytesPerRow * capture.image.height }
    }

    private(set) var entries: [Entry] = []
    private let maxCount: Int
    private let byteBudget: Int

    init(maxCount: Int = 12, byteBudget: Int = 96 * 1024 * 1024) {
        self.maxCount = max(1, maxCount)
        self.byteBudget = max(1, byteBudget)
    }

    func insert(_ capture: CapturedImage, disposable: Bool) {
        entries.removeAll { $0.id == capture.id }
        entries.insert(Entry(capture: capture, disposable: disposable), at: 0)
        var bytes = 0
        let keep = entries.prefix(maxCount).prefix { entry in
            bytes += entry.cost
            return entry.id == capture.id || bytes <= byteBudget
        }.count
        if keep < entries.count { entries.removeLast(entries.count - keep) }
    }

    func markKept(_ id: UUID) {
        if let index = entries.firstIndex(where: { $0.id == id }) { entries[index].disposable = false }
    }
}

struct RecentCapturesView: View {
    static let size = CGSize(width: 490, height: 510)
    let recent: RecentCaptures
    let open: (CapturedImage) -> Void
    let copy: (CapturedImage) async -> Bool
    let keep: (CapturedImage) async -> Bool
    let library: () -> Void
    let canKeep: () -> Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @LocalState private var copied: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.md) {
            HStack {
                Text("Recent captures").font(DS.title)
                Spacer()
                Button("Open Library", action: library).buttonStyle(QuietButtonStyle())
            }
            if recent.entries.isEmpty {
                VStack(spacing: DS.sm) {
                    Icon("images", size: DS.xl)
                    Text("No captures in this session").font(DS.emphasis)
                    Text("New captures will appear here.").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(recent.entries) { entry in
                            row(entry)
                            if entry.id != recent.entries.last?.id { Hairline() }
                        }
                    }
                    .padding(.horizontal, DS.md)
                    .background(DS.card(scheme), in: RoundedRectangle(cornerRadius: DS.md))
                }
            }
        }
        .padding(DS.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(GlassSurface(radius: DS.md))
    }

    private func row(_ entry: RecentCaptures.Entry) -> some View {
        let image = entry.capture.image
        return HStack(spacing: DS.sm) {
            Button { open(entry.capture) } label: {
                HStack(spacing: DS.md) {
                    Image(decorative: image, scale: 1).resizable().scaledToFit()
                        .frame(width: DS.Ask.thumbnail.width, height: DS.Ask.thumbnail.height)
                        .clipShape(RoundedRectangle(cornerRadius: DS.xs))
                    VStack(alignment: .leading, spacing: DS.xs) {
                        Text(entry.disposable ? "Disposable capture" : entry.capture.source).font(DS.emphasis).lineLimit(1)
                        Text("\(image.width) × \(image.height) · \(entry.capture.date.formatted(date: .omitted, time: .shortened))")
                            .font(DS.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open in editor")
            if entry.disposable && canKeep() {
                IconButton("tray-arrow-down", label: "Keep in Library") { Task { _ = await keep(entry.capture) } }
            }
            IconButton(copied == entry.id ? "check" : "copy", label: copied == entry.id ? "Copied" : "Copy image") {
                Task {
                    guard await copy(entry.capture) else { return }
                    withAnimation(DS.Motion.gentle(reduced)) { copied = entry.id }
                    try? await Task.sleep(for: .seconds(1.3))
                    if copied == entry.id { copied = nil }
                }
            }
        }.padding(.vertical, DS.sm)
    }
}
