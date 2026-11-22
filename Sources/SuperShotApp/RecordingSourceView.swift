import AppKit
import Capture
import DesignSystem
import SwiftUI

struct RecordingSetupView: View {
    static let preferredSize = CGSize(width: 640, height: 665)
    static let minimumSize = CGSize(width: 480, height: 555)
    static let permissionSize = CGSize(width: 505, height: 283)

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var model: RecordingSetup
    let permission: ScreenPermission
    let loadWindows: () -> Void
    let openPrivacy: () -> Void
    let record: () -> Void
    var chooseArea: () -> Void = {}
    var previewSource: () -> Void = {}
    var resetPreview: () -> Void = {}
    var cancelStart: () -> Void = {}
    var refreshDisplays: () -> Void = {}
    var permissionChanged: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: DS.lg) {
            WorkspaceHeader(title: "Record Screen", subtitle: "Choose a source and set up your recording.", icon: "monitor")
                .padding(.horizontal, DS.xl)
            ScrollView {
                VStack(alignment: .leading, spacing: DS.md) {
                    if permission.state == .authorized {
                        sourceSection
                        optionSections
                    } else {
                        permissionSection
                    }
                }
                .padding(.horizontal, DS.xl)
                .padding(.vertical, DS.xs)
            }
            .disabled(model.phase != .ready)
            footer
                .padding(.horizontal, DS.xl)
        }
        .padding(.top, DS.xxl)
        .padding(.bottom, DS.lg)
        .tint(DS.accent)
        .background(WorkspaceBackground())
        .onChange(of: model.source) { _, _ in resetPreview() }
        .onChange(of: model.mode) { _, mode in if mode == .window { loadWindows() } }
        .onChange(of: permission.state) { _, state in
            permissionChanged()
            if state == .authorized, model.mode == .window { loadWindows() }
            if state != .authorized { resetPreview() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            if model.phase == .ready { refreshDisplays() }
        }
        .animation(DS.Motion.panel(reduceMotion), value: permission.state)
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: DS.md) {
            sectionTitle("Source")
            modePicker
            if model.mode == .window {
                windowPicker
            } else {
                displayPicker
                if model.mode == .area { areaPicker }
            }
            if model.mode == .window {
                HStack(spacing: DS.sm) {
                    if model.source != nil { previewActions }
                    Spacer(minLength: DS.xs)
                    quietAction("Refresh", icon: "arrow-clockwise", action: loadWindows)
                        .disabled(model.loadingWindows)
                        .accessibilityLabel("Refresh window list")
                        .help("Refresh window list")
                }
            } else if model.source != nil, model.mode != .area || model.preview != nil {
                previewActions
            }
            if let image = model.preview {
                Image(image, scale: 1, label: Text("Preview of \(model.selectedName)"))
                    .resizable().scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: DS.xxl * 4)
                    .background(DS.card(scheme), in: RoundedRectangle(cornerRadius: DS.controlRadius))
                    .clipShape(RoundedRectangle(cornerRadius: DS.controlRadius))
            }
        }
    }

    private var modePicker: some View {
        GlassGroup(spacing: DS.xs) {
            HStack(spacing: DS.xs) {
                ForEach(RecordingSetup.Mode.allCases, id: \.self) { mode in
                    let selected = model.mode == mode
                    Button {
                        withAnimation(DS.Motion.snappy(reduceMotion)) { model.mode = mode }
                    } label: {
                        Label { Text(mode.rawValue) } icon: { Icon(mode.icon, weight: selected ? .fill : .regular, size: DS.icon) }
                            .font(selected ? DS.emphasis : DS.body)
                            .foregroundStyle(selected ? DS.actionInk(scheme) : Color.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: DS.toolButtonSize)
                            .background(selected ? DS.accent.opacity(DS.subtleOpacity) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: DS.controlRadius))
                            .overlay {
                                if selected {
                                    RoundedRectangle(cornerRadius: DS.controlRadius)
                                        .strokeBorder(DS.accent.opacity(DS.outlineOpacity * 2))
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(DS.xs)
            .background(DS.card(scheme), in: RoundedRectangle(cornerRadius: DS.smallRadius))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recording source type")
    }

    @ViewBuilder private var displayPicker: some View {
        if model.displays.isEmpty {
            Text("No displays are available.").font(DS.body).foregroundStyle(.secondary)
        } else {
            RecordingDisplayMap(choices: model.displays, selection: model.displayID, select: selectDisplay)
            HStack(spacing: DS.sm) {
                Picker("Display", selection: Binding(get: { model.displayID }, set: selectDisplay)) {
                    ForEach(model.displays) { screen in Text(screen.name).tag(Optional(screen.id)) }
                }
                .font(DS.body)
                .lineLimit(1)
                Spacer(minLength: DS.xs)
                if let detail = model.displays.first(where: { $0.id == model.displayID })?.detail {
                    Text(detail).font(DS.mono).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func selectDisplay(_ id: UInt32?) {
        guard id != model.displayID else { return }
        model.displayID = id
        model.area = nil
    }

    private var areaPicker: some View {
        HStack(spacing: DS.sm) {
            if let area = model.area {
                Text("\(Int(area.width.rounded()).formatted()) × \(Int(area.height.rounded()).formatted()) pt")
                    .font(DS.mono).foregroundStyle(.secondary)
            } else {
                Text("Drag to mark an area on the selected display.").font(DS.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: DS.xs)
            if model.area != nil, model.preview == nil { previewActions }
            quietAction(model.area == nil ? "Select Area" : "Change Area", icon: "selection", action: chooseArea)
                .disabled(model.displayID == nil)
        }
    }

    private var windowPicker: some View {
        HStack(spacing: DS.sm) {
            if !model.windows.isEmpty {
                Picker("Window", selection: $model.windowID) {
                    ForEach(model.windows) { window in Text(window.name).lineLimit(1).tag(Optional(window.id)) }
                }
                .font(DS.body)
                .lineLimit(1)
                if let size = model.windows.first(where: { $0.id == model.windowID })?.detail {
                    Text(size).font(DS.mono).foregroundStyle(.secondary)
                }
            } else if model.loadingWindows {
                ProgressView("Finding windows…").controlSize(.small).font(DS.body)
            } else {
                Text("No app windows are available.").font(DS.body).foregroundStyle(.secondary)
            }
            Spacer(minLength: DS.xs)
        }
    }

    private var previewActions: some View {
        HStack(spacing: DS.sm) {
            quietAction(model.preview == nil ? "Preview Source" : "Refresh Preview",
                        icon: model.preview == nil ? "eye" : "arrow-clockwise", action: previewSource)
                .disabled(model.loadingPreview)
            if model.loadingPreview {
                ProgressView().controlSize(.small).accessibilityLabel("Loading preview")
            } else if model.preview != nil {
                quietAction("Hide Preview", icon: "eye-slash", action: resetPreview)
            }
        }
    }

    private var optionSections: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DS.md) {
                inputSection.frame(minWidth: DS.xxl * 4)
                pointerSection.frame(minWidth: DS.xxl * 4)
                outputSection.frame(minWidth: DS.xxl * 5.75)
            }
            VStack(spacing: DS.md) {
                HStack(alignment: .top, spacing: DS.md) {
                    inputSection
                    pointerSection
                }
                outputSection
            }
        }
    }

    private var inputSection: some View {
        optionPanel("Inputs") {
            switchRow("System audio", value: $model.options.systemAudio)
            switchRow("Microphone", value: $model.options.microphone)
            if model.options.microphone {
                Picker("Microphone input", selection: $model.options.microphoneDeviceID) {
                    Text("System default").tag(nil as String?)
                    ForEach(model.microphones) { device in Text(device.name).tag(Optional(device.id)) }
                }
                .labelsHidden()
            }
            switchRow("Camera", value: $model.options.camera)
            if model.options.camera {
                VStack(alignment: .leading, spacing: DS.xs) {
                    Text("Camera layout").font(DS.caption).foregroundStyle(.secondary).accessibilityHidden(true)
                    Picker("Camera layout", selection: $model.cameraLayout) {
                        ForEach(RecordingCameraLayout.allCases, id: \.self) { layout in Text(layout.title).tag(layout) }
                    }
                    .labelsHidden()
                    .help("Change the camera layout later in the recording editor.")
                }
            }
        }
    }

    private var outputSection: some View {
        optionPanel("Output") {
            optionRow("Resolution") {
                Picker("Resolution", selection: $model.options.resolution) {
                    ForEach(RecordingResolution.allCases, id: \.self) { resolution in Text(resolution.title).tag(resolution) }
                }
            }
            optionRow("Frame rate") {
                Picker("Frame rate", selection: $model.options.frameRate) {
                    ForEach(RecordingFrameRate.allCases, id: \.self) { rate in Text("\(rate.rawValue) fps").tag(rate) }
                }
            }
            optionRow("Countdown") {
                Picker("Countdown", selection: $model.delay) {
                    Text("Off").tag(0)
                    Text("3 seconds").tag(3)
                    Text("5 seconds").tag(5)
                    Text("10 seconds").tag(10)
                }
            }
        }
    }

    private var pointerSection: some View {
        optionPanel("Pointer") {
            switchRow("Show pointer", value: $model.options.showCursor)
            switchRow("Highlight clicks", value: $model.options.showClicks)
            if model.mode != .window {
                switchRow("Zoom at clicks", value: $model.options.zoomOnClicks)
                    .help("Adds editable zooms to the timeline.")
            }
        }
    }

    private func optionPanel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.sm) {
            sectionTitle(title)
            Hairline()
            content()
        }
        .font(DS.body)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func optionRow<Content: View>(_ title: String, @ViewBuilder control: () -> Content) -> some View {
        HStack(spacing: DS.xs) {
            Text(title).fixedSize(horizontal: true, vertical: false).accessibilityHidden(true)
            Spacer(minLength: DS.xs)
            control().labelsHidden().fixedSize()
        }
    }

    private func switchRow(_ title: String, value: Binding<Bool>) -> some View {
        optionRow(title) { Toggle(title, isOn: value).toggleStyle(SwitchStyle()) }
    }

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: DS.md) {
            Label { Text("Allow Screen Recording to choose a source.") } icon: {
                Icon("shield-check", size: DS.iconSize)
            }
            .font(DS.emphasis)
            HStack(spacing: DS.sm) {
                if !permission.hasRequested {
                    quietAction("Request Access", icon: "shield-check", action: permission.requestAccess)
                }
                quietAction("Open System Settings", icon: "gear-six", action: openPrivacy)
            }
        }
        .padding(DS.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(GlassSurface(radius: DS.groupRadius))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: DS.sm) {
            if let error = model.error {
                Label { Text(error).textSelection(.enabled) } icon: { Icon("warning-circle", size: DS.icon) }
                    .font(DS.caption).foregroundStyle(.primary)
            }
            HStack(spacing: DS.sm) {
                if let countdown = model.countdown {
                    Label { Text("Starting in \(countdown)…").monospacedDigit() } icon: { Icon("timer", size: DS.icon) }
                        .font(DS.emphasis)
                } else if model.phase == .starting {
                    ProgressView("Starting…").controlSize(.small).font(DS.body)
                } else {
                    Text("Recordings are saved on this Mac.").font(DS.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: DS.xs)
                if model.phase == .starting {
                    quietAction("Cancel", icon: "x", action: cancelStart).keyboardShortcut(.cancelAction)
                } else {
                    RecordingAction(title: "Record", icon: "circle", action: record)
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.phase != .ready || model.source == nil || permission.state != .authorized)
                }
            }
        }
        .padding(DS.md)
        .modifier(GlassSurface(radius: DS.groupRadius))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(DS.emphasis).accessibilityAddTraits(.isHeader)
    }

    private func quietAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label { Text(title) } icon: { Icon(icon, size: DS.icon) }
        }
        .buttonStyle(QuietButtonStyle())
    }
}

private struct RecordingDisplayMap: View {
    @Environment(\.colorScheme) private var scheme
    let choices: [RecordingChoice]
    let selection: UInt32?
    let select: (UInt32) -> Void

    private var frames: [UInt32: CGRect] {
        Dictionary(uniqueKeysWithValues: choices.enumerated().map { index, display in
            // Previews without desktop metadata still lay out as separate displays.
            (display.id, display.frame ?? CGRect(x: CGFloat(index) * 1600, y: 0, width: 1440, height: 900))
        })
    }

    var body: some View {
        let frames = frames
        let bounds = frames.values.reduce(CGRect.null) { $0.union($1) }
        GeometryReader { geometry in
            let scale = min(geometry.size.width / max(bounds.width, 1), geometry.size.height / max(bounds.height, 1))
            ForEach(choices) { display in
                if let frame = frames[display.id] {
                    let selected = display.id == selection
                    let width = max(1, frame.width * scale - DS.xs)
                    let height = max(1, frame.height * scale - DS.xs)
                    Button { select(display.id) } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: DS.controlRadius)
                                .fill(selected ? DS.accent.opacity(DS.outlineOpacity) : DS.card(scheme))
                                .strokeBorder(selected ? DS.accent : DS.hairline(scheme))
                            if width >= DS.xxl, height >= DS.toolButton {
                                VStack(spacing: DS.xs) {
                                    Icon("monitor", weight: selected ? .fill : .regular, size: DS.iconSize)
                                    if width >= DS.xxl * 2.5, height >= DS.xxl {
                                        Text(display.name).font(DS.caption).lineLimit(1)
                                    }
                                }
                                .foregroundStyle(selected ? DS.actionInk(scheme) : Color.secondary)
                                .padding(.horizontal, DS.xs)
                            }
                        }
                        .frame(width: width, height: height)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    .position(x: geometry.size.width / 2 + (frame.midX - bounds.midX) * scale,
                              y: geometry.size.height / 2 + (bounds.midY - frame.midY) * scale)
                    .zIndex(selected ? 1 : 0)
                    .help(display.name)
                    .accessibilityLabel(display.name)
                    .accessibilityValue(display.detail ?? "")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .frame(height: DS.xxl * 2.5)
        .padding(DS.sm)
        .background(DS.card(scheme), in: RoundedRectangle(cornerRadius: DS.controlRadius))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Display arrangement")
    }
}

struct RecordingControls: View {
    static let preferredSize = CGSize(width: 320, height: 68)

    let model: RecordingSetup
    let stop: () -> Void

    var body: some View {
        GlassGroup {
            HStack(spacing: DS.md) {
                Icon("circle", weight: .fill, size: DS.icon)
                    .foregroundStyle(DS.danger).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.xs) {
                    HStack(spacing: DS.sm) {
                        Text(model.phase == .finishing ? "Saving…" : "Recording").font(DS.emphasis)
                        if let start = model.startedAt, model.phase == .recording {
                            Text(start, style: .timer).font(DS.mono).foregroundStyle(.secondary)
                                .accessibilityLabel("Elapsed recording time")
                        }
                    }
                    Label { Text(model.selectedName).lineLimit(1) } icon: { Icon(model.mode.icon, size: DS.icon) }
                        .font(DS.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if model.phase == .finishing {
                    ProgressView().controlSize(.small).accessibilityLabel("Saving recording")
                } else {
                    RecordingAction(title: "Stop", icon: "stop", action: stop)
                        .accessibilityLabel("Stop recording")
                }
            }
            .padding(.horizontal, DS.md)
            .padding(.vertical, DS.sm)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(GlassSurface(radius: DS.groupRadius, interactive: true))
        }
        .padding(DS.xs)
    }
}
