import Capture
import DesignSystem
import SwiftUI

extension RecordingAnnotation.Kind {
    var title: String {
        switch self {
        case .outline: "Rectangle"
        case .arrow: "Arrow"
        case .text: "Text"
        case .spotlight: "Spotlight"
        case .cover: "Cover"
        case .highlight: "Highlight"
        case .blur: "Blur"
        }
    }

    var icon: String {
        switch self {
        case .outline: "rectangle"
        case .arrow: "arrow-up-right"
        case .text: "text-t"
        case .spotlight: "crosshair-simple"
        case .cover: "eye-slash"
        case .highlight: "pencil-simple"
        case .blur: "drop"
        }
    }

    var usesInk: Bool {
        switch self {
        case .outline, .arrow, .text, .highlight: true
        case .cover, .blur, .spotlight: false
        }
    }
}

struct RecordingMarkupOptions: View {
    @Bindable var model: RecordingEditorModel
    @Binding var placing: RecordingAnnotation.Kind?
    @Binding var ink: RecordingAnnotation.Ink

    var body: some View {
        VStack(alignment: .leading, spacing: DS.md) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.xs), GridItem(.flexible(), spacing: DS.xs)], spacing: DS.xs) {
                ForEach(RecordingAnnotation.Kind.allCases, id: \.self) { kind in
                    RecordingToolTile(title: kind.title, icon: kind.icon, selected: placing == kind, compact: true) {
                        if placing == kind { placing = nil }
                        else {
                            if model.playing { model.playOrPause() }
                            placing = kind
                        }
                    }
                    .disabled(!model.canPlaceTimedEdit)
                }
            }
            if let placing {
                Text(placing == .text ? "Click the video to place text." : "Drag over the video to draw.")
                    .font(DS.body).foregroundStyle(.secondary)
                if placing.usesInk { swatches(selection: $ink) }
                HStack(spacing: DS.sm) {
                    Button("Place in center") { placeInCenter(placing) }.buttonStyle(QuietButtonStyle())
                    Button("Cancel") { self.placing = nil }.buttonStyle(.plain).font(DS.body)
                }
            } else if model.edits?.annotations?.isEmpty != false {
                Text("Choose a tool and place it on the video at the current playhead.")
                    .font(DS.body).foregroundStyle(.secondary)
            }
            if let items = model.edits?.annotations, !items.isEmpty {
                Hairline()
                Text("Timed annotations").font(DS.emphasis)
                ForEach(items) { item in
                    editRow(item)
                }
            }
        }
    }

    private func editRow(_ item: RecordingAnnotation) -> some View {
        VStack(alignment: .leading, spacing: DS.sm) {
            HStack(spacing: DS.xs) {
                RecordingToolTile(title: item.kind.title, icon: item.kind.icon, selected: model.selectedAnnotation == item.id,
                                  detail: recordingPlayheadCode(item.range.start)) {
                    model.selectedAnnotation = item.id
                    placing = nil
                    model.seek(item.range.start)
                }
                IconButton("x", label: "Remove \(item.kind.title) at \(recordingPlayheadCode(item.range.start))", size: DS.xl) {
                    model.removeAnnotation(item.id)
                }
            }
            if model.selectedAnnotation == item.id {
                RecordingTimeFields(range: item.range, fullRange: model.fullRange) { range in
                    model.editAnnotation(item.id) { $0.range = range }
                    model.seek(range.start)
                }
                if item.kind == .text {
                    RecordingAnnotationLabel(text: item.text) { text in model.editAnnotation(item.id) { $0.text = text } }
                }
                if item.kind.usesInk {
                    swatches(selection: Binding(get: { item.ink }, set: { ink in
                        model.editAnnotation(item.id) { $0.ink = ink }
                    }))
                }
            }
        }
    }

    private func swatches(selection: Binding<RecordingAnnotation.Ink>) -> some View {
        HStack(spacing: DS.sm) {
            Text("Color").font(DS.body)
            ForEach(RecordingAnnotation.Ink.allCases, id: \.self) { color in
                Button {
                    selection.wrappedValue = color
                } label: {
                    Circle().fill(Color(cgColor: color.color)).frame(width: DS.lg, height: DS.lg)
                        .padding(DS.xs)
                        .overlay(Circle().strokeBorder(selection.wrappedValue == color ? Color.primary : Color.clear))
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(color.rawValue.capitalized)
                .accessibilityAddTraits(selection.wrappedValue == color ? .isSelected : [])
            }
        }
    }

    private func placeInCenter(_ kind: RecordingAnnotation.Kind) {
        model.addAnnotation(kind, from: CGPoint(x: 0.35, y: 0.38), to: CGPoint(x: 0.65, y: 0.62), ink: ink)
        placing = nil
    }
}

/// The overlay uses the same top-left, aspect-fit coordinates as the rendered annotation.
struct RecordingMarkupCanvas: View {
    let model: RecordingEditorModel
    @Binding var placing: RecordingAnnotation.Kind?
    let ink: RecordingAnnotation.Ink
    @GestureState private var drag: DragGesture.Value?
    @GestureState private var resize: DragGesture.Value?

    var body: some View {
        GeometryReader { geometry in
            if model.pixelSize.width > 0, model.pixelSize.height > 0 {
                let scale = min(geometry.size.width / model.pixelSize.width, geometry.size.height / model.pixelSize.height)
                let size = CGSize(width: model.pixelSize.width * scale, height: model.pixelSize.height * scale)
                ZStack(alignment: .topLeading) {
                    if let placing {
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .gesture(drawing(kind: placing, in: size))
                            .accessibilityHidden(true)
                        if let drag {
                            outline(from: drag.startLocation, to: drag.location, kind: placing, frame: size, isDraft: true)
                        }
                    } else if let item = model.edits?.annotations?.first(where: { $0.id == model.selectedAnnotation }),
                              item.range.start <= model.sourceTime, model.sourceTime < item.range.end, !model.playing {
                        selectedItem(item, in: size)
                    }
                }
                .frame(width: size.width, height: size.height)
                .clipped()
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
        }
    }

    private func drawing(kind: RecordingAnnotation.Kind, in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($drag) { value, draft, _ in draft = value }
            .onEnded { drag in
                guard size.width > 0, size.height > 0 else { return }
                let width = abs(drag.translation.width)
                let height = abs(drag.translation.height)
                guard kind == .text || (kind == .arrow ? hypot(width, height) >= DS.sm : min(width, height) >= DS.sm) else { return }
                model.addAnnotation(kind, from: normalized(drag.startLocation, in: size),
                                    to: normalized(drag.location, in: size), ink: ink)
                placing = nil
            }
    }

    private func selectedItem(_ item: RecordingAnnotation, in size: CGSize) -> some View {
        let start = CGPoint(x: item.start.x * size.width, y: item.start.y * size.height)
        let end = CGPoint(x: item.end.x * size.width, y: item.end.y * size.height)
        let draftEnd = resize.map { bounded(end, adding: $0.translation, in: size) } ?? end
        let area = selectionBounds(from: start, to: draftEnd, kind: item.kind)
        let delta = drag.map { translation(for: item, delta: $0.translation, in: size) } ?? .zero
        return ZStack(alignment: .topLeading) {
            outline(from: start, to: draftEnd, kind: item.kind, frame: size, isDraft: false)
            Rectangle().fill(.clear).contentShape(Rectangle())
                .frame(width: area.width + DS.sm, height: area.height + DS.sm)
                .offset(x: area.minX - DS.xs, y: area.minY - DS.xs)
                .accessibilityHidden(true)
                .gesture(DragGesture(coordinateSpace: .global)
                    .updating($drag) { value, draft, _ in draft = value }
                    .onEnded { drag in
                        let delta = translation(for: item, delta: drag.translation, in: size)
                        model.editAnnotation(item.id) {
                            $0.start = normalized(CGPoint(x: start.x + delta.width, y: start.y + delta.height), in: size)
                            if item.kind != .text {
                                $0.end = normalized(CGPoint(x: end.x + delta.width, y: end.y + delta.height), in: size)
                            }
                        }
                    })
            if item.kind != .text {
                Circle().fill(DS.accentBright)
                    .overlay(Circle().strokeBorder(DS.white, lineWidth: DS.stroke))
                    .frame(width: DS.sm, height: DS.sm)
                    .padding(DS.xs)
                    .contentShape(Rectangle())
                    .position(draftEnd)
                    .accessibilityHidden(true)
                    .gesture(DragGesture(coordinateSpace: .global)
                        .updating($resize) { value, draft, _ in draft = value }
                        .onEnded { value in
                            let point = bounded(end, adding: value.translation, in: size)
                            let width = abs(point.x - start.x)
                            let height = abs(point.y - start.y)
                            guard item.kind == .arrow ? hypot(width, height) >= DS.sm : min(width, height) >= DS.sm else { return }
                            model.editAnnotation(item.id) { $0.end = normalized(point, in: size) }
                        })
            }
        }
        .offset(x: delta.width, y: delta.height)
    }

    private func bounded(_ point: CGPoint, adding delta: CGSize, in size: CGSize) -> CGPoint {
        CGPoint(x: min(size.width, max(0, point.x + delta.width)), y: min(size.height, max(0, point.y + delta.height)))
    }

    private func outline(from start: CGPoint, to end: CGPoint, kind: RecordingAnnotation.Kind,
                         frame: CGSize, isDraft: Bool) -> some View {
        let area = selectionBounds(from: start, to: end, kind: kind)
        return Path { path in
            if isDraft && kind == .arrow {
                path.move(to: start)
                path.addLine(to: end)
            } else {
                path.addRect(area)
            }
        }
        .stroke(DS.accentBright, style: StrokeStyle(lineWidth: 2 * DS.stroke, dash: [DS.xs, DS.xs]))
        .frame(width: frame.width, height: frame.height)
        .allowsHitTesting(false)
    }

    private func selectionBounds(from start: CGPoint, to end: CGPoint, kind: RecordingAnnotation.Kind) -> CGRect {
        if kind == .text { return CGRect(x: start.x, y: start.y, width: DS.xxl * 1.8, height: DS.xl) }
        return CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                      width: max(DS.xs, abs(start.x - end.x)), height: max(DS.xs, abs(start.y - end.y)))
    }

    private func normalized(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: min(1, max(0, point.x / size.width)), y: min(1, max(0, point.y / size.height)))
    }

    private func translation(for item: RecordingAnnotation, delta: CGSize, in size: CGSize) -> CGSize {
        let end = item.kind == .text ? item.start : item.end
        return CGSize(width: min((1 - max(item.start.x, end.x)) * size.width, max(-min(item.start.x, end.x) * size.width, delta.width)),
                      height: min((1 - max(item.start.y, end.y)) * size.height, max(-min(item.start.y, end.y) * size.height, delta.height)))
    }
}

struct RecordingCameraOptions: View {
    @Bindable var model: RecordingEditorModel
    @LocalState private var newLayout: RecordingCameraLayout = .circle

    var body: some View {
        VStack(alignment: .leading, spacing: DS.md) {
            if model.hasCamera {
                Picker("Default layout", selection: Binding(get: { model.edits?.cameraLayout ?? .bottomRight }, set: model.setCameraLayout)) {
                    ForEach(RecordingCameraLayout.allCases, id: \.self) { Text($0.title).tag($0) }
                }.font(DS.body)
                Hairline()
                Text("Timed layouts").font(DS.emphasis)
                Picker("Layout to add", selection: $newLayout) {
                    ForEach(RecordingCameraLayout.allCases, id: \.self) { Text($0.title).tag($0) }
                }.font(DS.body)
                Button("Add at playhead") { model.addCameraSegment(newLayout) }
                    .buttonStyle(QuietButtonStyle()).disabled(!model.canPlaceTimedEdit)
                ForEach(model.edits?.cameraSegments ?? []) { segment in
                    editRow(segment)
                }
            } else {
                Text("This recording has no camera track. To add one, turn on Camera in the recorder before starting.")
                    .font(DS.body).foregroundStyle(.secondary)
            }
        }
    }

    private func editRow(_ segment: RecordingCameraSegment) -> some View {
        VStack(alignment: .leading, spacing: DS.sm) {
            HStack(spacing: DS.xs) {
                RecordingToolTile(title: segment.layout.title, icon: "video-camera", selected: model.selectedCameraSegment == segment.id,
                                  detail: recordingPlayheadCode(segment.range.start)) {
                    model.selectedCameraSegment = segment.id
                    model.seek(segment.range.start)
                }
                IconButton("x", label: "Remove camera change at \(recordingPlayheadCode(segment.range.start))", size: DS.xl) {
                    model.removeCameraSegment(segment.id)
                }
            }
            if model.selectedCameraSegment == segment.id {
                Picker("Layout", selection: Binding(get: { segment.layout }, set: { layout in
                    model.editCameraSegment(segment.id) { $0.layout = layout }
                })) {
                    ForEach(RecordingCameraLayout.allCases, id: \.self) { Text($0.title).tag($0) }
                }.font(DS.body)
                RecordingTimeFields(range: segment.range, fullRange: model.fullRange) { range in
                    model.editCameraSegment(segment.id) { $0.range = range }
                    model.seek(range.start)
                }
            }
        }
    }
}

private struct RecordingToolTile: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    let icon: String
    let selected: Bool
    var detail: String?
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.xs) {
                Icon(icon, weight: selected ? .fill : .regular, size: DS.icon)
                Text(title).font(DS.body).lineLimit(1)
                Spacer(minLength: 0)
                if let detail { Text(detail).font(DS.mono).foregroundStyle(Color.secondary) }
            }
            .foregroundStyle(selected ? DS.actionInk(scheme) : .primary)
            .padding(.horizontal, DS.sm)
            .padding(.vertical, compact ? DS.xs : DS.sm)
            .background(selected ? DS.accent.opacity(DS.outlineOpacity) : DS.card(scheme),
                        in: RoundedRectangle(cornerRadius: DS.controlRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct RecordingAnnotationLabel: View {
    let text: String
    let update: (String) -> Void
    @LocalState private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Annotation text", text: $draft)
            .font(DS.body)
            .focused($focused)
            .onSubmit(commit)
            .onChange(of: focused) { _, value in if !value { commit() } }
            .onChange(of: text, initial: true) { _, next in draft = next }
    }

    private func commit() {
        let trimmed = String(draft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
        if trimmed.isEmpty { draft = text }
        else if trimmed != text { update(trimmed) }
    }
}

private struct RecordingTimeFields: View {
    let range: RecordingRange
    let fullRange: RecordingRange?
    let update: (RecordingRange) -> Void
    @LocalState private var start = ""
    @LocalState private var end = ""
    @LocalState private var invalid = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.xs) {
            HStack(spacing: DS.sm) {
                field("Start (s)", value: $start)
                field("End (s)", value: $end)
                IconButton("check", label: "Apply source times", size: DS.xl, action: commit)
            }
            if invalid {
                Text("Enter a start and a later end within the source recording.").font(DS.caption).foregroundStyle(.secondary)
            }
        }.onChange(of: range, initial: true) { _, next in
            start = next.start.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
            end = next.end.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
            invalid = false
        }
    }

    private func field(_ title: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: DS.xs) {
            Text(title).font(DS.caption).foregroundStyle(.secondary)
            TextField(title, text: value).font(DS.mono).onSubmit(commit)
        }
    }

    private func commit() {
        let style = FloatingPointFormatStyle<Double>.number
        guard let fullRange, let start = try? style.parseStrategy.parse(start),
              let end = try? style.parseStrategy.parse(end), start >= fullRange.start - 0.005, end <= fullRange.end + 0.005,
              let replacement = RecordingRange(start: max(start, fullRange.start), end: min(end, fullRange.end)) else {
            invalid = true
            return
        }
        invalid = false
        if range != replacement { update(replacement) }
    }
}

struct RecordingZoomFocusView: View {
    let pixelSize: CGSize
    let select: (CGPoint) -> Void

    var body: some View {
        GeometryReader { geometry in
            if pixelSize.width > 0, pixelSize.height > 0 {
                let scale = min(geometry.size.width / pixelSize.width, geometry.size.height / pixelSize.height)
                let width = pixelSize.width * scale
                let height = pixelSize.height * scale
                RoundedRectangle(cornerRadius: DS.controlRadius)
                    .strokeBorder(DS.accentBright, style: StrokeStyle(lineWidth: 2 * DS.stroke, dash: [DS.sm, DS.xs]))
                    .contentShape(Rectangle())
                    .frame(width: width, height: height)
                    .gesture(SpatialTapGesture().onEnded { tap in
                        guard width > 0, height > 0 else { return }
                        select(CGPoint(x: min(1, max(0, tap.location.x / width)), y: min(1, max(0, 1 - tap.location.y / height))))
                    })
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    .accessibilityHidden(true)
            }
        }
    }
}
