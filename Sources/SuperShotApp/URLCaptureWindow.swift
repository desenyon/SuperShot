import AppKit
import Capture
import DesignSystem
import Observation
import SwiftUI

@MainActor final class URLCaptureWindowController: NSObject, NSWindowDelegate {
    static let panelSize = CGSize(width: DS.welcomeSize.width + DS.xxl, height: DS.welcomeSize.height)
    private static let minimumSize = CGSize(width: 340, height: 280)

    private let onCapture: (CapturedImage) -> Void
    private let state = URLCapturePanelState()
    private var window: NSWindow?

    init(onCapture: @escaping (CapturedImage) -> Void) {
        self.onCapture = onCapture
    }

    static func fittingSize(available: CGSize) -> CGSize {
        DS.fittingWindowSize(preferred: panelSize, available: available)
    }

    func present() {
        state.refreshBrowser()
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }

        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let size = screen.map { Self.fittingSize(available: $0.visibleFrame.size) } ?? Self.panelSize
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false, screen: screen)
        window.title = "Capture Webpage"
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.delegate = self
        let panel = URLCapturePanel(state: state, close: { [weak window] in window?.close() }) { [weak self] capture in
            guard let self else { return }
            self.window?.close()
            self.onCapture(capture)
        }
        let host = NSHostingController(rootView: panel)
        // A scroll view should adapt to the window without contributing a preferred window size.
        host.sizingOptions = []
        window.contentViewController = host
        window.contentMinSize = CGSize(width: min(size.width, Self.minimumSize.width),
                                       height: min(size.height, Self.minimumSize.height))
        window.setContentSize(size)
        if let visibleFrame = screen?.visibleFrame {
            window.setFrameOrigin(CGPoint(x: visibleFrame.midX - window.frame.width / 2,
                                          y: visibleFrame.midY - window.frame.height / 2))
        } else {
            window.center()
        }
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func cancel() { state.cancel() }

    func windowWillClose(_ notification: Notification) {
        state.cancel()
        window = nil
    }
}

@MainActor @Observable final class URLCapturePanelState {
    enum Breakpoint: String, CaseIterable {
        case desktop = "Desktop"
        case tablet = "Tablet"
        case phone = "Phone"
        case custom = "Custom"

        var size: (width: Int, height: Int)? {
            switch self {
            case .desktop: (1440, 900)
            case .tablet: (820, 1180)
            case .phone: (390, 844)
            case .custom: nil
            }
        }
    }

    enum PreviewScenario { case custom, capturing, failed, unavailable }

    var address = "" { didSet { error = nil } }
    var breakpoint = Breakpoint.desktop { didSet { error = nil } }
    var customWidth = "1440" { didSet { error = nil } }
    var customHeight = "900" { didSet { error = nil } }
    var appearance = URLCaptureRequest.Appearance.light { didSet { error = nil } }
    var scope = URLCaptureRequest.Scope.fullPage { didSet { error = nil } }
    private(set) var isCapturing = false
    private(set) var error: URLCaptureError?
    private(set) var browserName: String?

    @ObservationIgnored private let resolveBrowser: () -> String?
    @ObservationIgnored private let render: (URLCaptureRequest) async throws -> CapturedImage
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var captureID: UUID?

    init(resolveBrowser: @escaping () -> String? = { URLCaptureService().browserName },
         render: @escaping (URLCaptureRequest) async throws -> CapturedImage = { try await URLCaptureService().capture($0) }) {
        self.resolveBrowser = resolveBrowser
        self.render = render
        browserName = resolveBrowser()
    }

    var dimensions: (width: Int, height: Int) {
        breakpoint.size ?? (Int(customWidth.trimmingCharacters(in: .whitespaces)) ?? 0,
                            Int(customHeight.trimmingCharacters(in: .whitespaces)) ?? 0)
    }

    var errorMessage: String? {
        if error == .invalidAddress && address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter the page URL."
        }
        return error?.errorDescription
    }

    var shouldRetry: Bool {
        guard let error else { return false }
        return error != .invalidAddress && error != .invalidSize && error != .pageTooLarge
    }

    func refreshBrowser() {
        browserName = resolveBrowser()
        if browserName != nil && error == .browserMissing { error = nil }
    }

    @discardableResult func capture(then complete: @escaping (CapturedImage) -> Void) -> Task<Void, Never>? {
        guard !isCapturing else { return nil }
        let request: URLCaptureRequest
        do {
            request = try URLCaptureRequest(address: address, width: dimensions.width, height: dimensions.height,
                                            appearance: appearance, scope: scope)
        } catch {
            self.error = (error as? URLCaptureError) ?? .invalidAddress
            return nil
        }
        refreshBrowser()
        guard browserName != nil else {
            error = .browserMissing
            return nil
        }
        error = nil
        isCapturing = true
        let id = UUID()
        captureID = id
        let render = self.render
        let task = Task { [weak self] in
            do {
                let capture = try await render(request)
                guard let self, captureID == id else { return }
                finish()
                complete(capture)
            } catch {
                guard let self, captureID == id else { return }
                finish()
                if !Task.isCancelled && !(error is CancellationError) {
                    self.error = (error as? URLCaptureError) ?? .pageUnavailable
                }
            }
        }
        operation = task
        return task
    }

    func cancel() {
        operation?.cancel()
        finish()
    }

    private func finish() {
        captureID = nil
        operation = nil
        isCapturing = false
    }

    static func preview(_ scenario: PreviewScenario) -> URLCapturePanelState {
        let state = URLCapturePanelState(resolveBrowser: { scenario == .unavailable ? nil : "Google Chrome" })
        state.address = "https://example.com"
        switch scenario {
        case .custom:
            state.breakpoint = .custom
            state.customWidth = "1280"
            state.customHeight = "800"
            state.appearance = .dark
        case .capturing: state.isCapturing = true
        case .failed: state.error = .navigationFailed
        case .unavailable: state.error = .browserMissing
        }
        return state
    }
}

struct URLCapturePanel: View {
    @Bindable var state: URLCapturePanelState
    var close: () -> Void = {}
    var complete: (CapturedImage) -> Void = { _ in }
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var addressFocused: Bool
    @Namespace private var selectionMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DS.lg) {
                WorkspaceHeader(title: "Capture Webpage", icon: "globe")
                source
            }
            .padding(.horizontal, DS.xl)
            .padding(.top, DS.lg)
            .padding(.bottom, DS.lg)
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: DS.md) {
                    viewport
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: DS.md) {
                            captureScope.frame(minWidth: 156)
                            pageAppearance.frame(minWidth: 112)
                        }
                        VStack(alignment: .leading, spacing: DS.md) {
                            captureScope
                            pageAppearance
                        }
                    }
                    Text(state.scope == .fullPage ? "Captures content below the fold at the selected width." :
                            "Captures the selected width and height at one time.")
                        .font(DS.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.xl)
                .padding(.vertical, DS.lg)
                .disabled(state.isCapturing)
                .opacity(state.isCapturing ? DS.mutedOpacity : 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { WorkspaceBackground() }
        .animation(DS.Motion.panel(reduceMotion), value: state.breakpoint)
        .animation(DS.Motion.gentle(reduceMotion), value: state.error)
        .animation(DS.Motion.gentle(reduceMotion), value: state.isCapturing)
        .defaultFocus($addressFocused, true)
        .onExitCommand { state.isCapturing ? state.cancel() : close() }
    }

    private var source: some View {
        VStack(alignment: .leading, spacing: DS.sm) {
            Text("Page URL").font(DS.emphasis)
            GlassGroup(spacing: DS.sm) {
                HStack(spacing: DS.sm) {
                    HStack(spacing: DS.sm) {
                        Icon("link", size: DS.icon).foregroundStyle(.secondary).accessibilityHidden(true)
                        TextField("https://example.com", text: $state.address)
                            .textFieldStyle(.plain)
                            .font(DS.body)
                            .accessibilityLabel("Page URL")
                            .focused($addressFocused)
                            .onSubmit(submit)
                            .disabled(state.isCapturing)
                    }
                    .padding(.horizontal, DS.md)
                    .frame(height: DS.barHeight)
                    .frame(maxWidth: .infinity)
                    .modifier(GlassSurface(radius: DS.controlRadius, backing: DS.card(scheme)))
                    .overlay {
                        if addressFocused {
                            RoundedRectangle(cornerRadius: DS.controlRadius)
                                .strokeBorder(DS.actionInk(scheme), lineWidth: DS.stroke)
                                .allowsHitTesting(false)
                        }
                    }
                    captureButton
                }
            }
            sourceStatus
        }
    }

    @ViewBuilder private var captureButton: some View {
        if state.isCapturing {
            Button { state.cancel() } label: {
                actionLabel("Cancel", icon: "stop", prominent: false)
            }
            .buttonStyle(PressableStyle())
        } else {
            Button(action: submit) {
                actionLabel(state.shouldRetry ? "Retry" : "Capture", icon: state.shouldRetry ? "arrows-clockwise" : "camera",
                            prominent: true)
            }
            .buttonStyle(PressableStyle())
            .keyboardShortcut(.defaultAction)
        }
    }

    private func actionLabel(_ title: String, icon: String, prominent: Bool) -> some View {
        HStack(spacing: DS.sm) {
            Icon(icon, size: DS.icon).accessibilityHidden(true)
            Text(title).font(DS.emphasis)
        }
        .foregroundStyle(prominent ? DS.onAccent : Color.primary)
        .padding(.horizontal, DS.md)
        .frame(height: DS.barHeight)
        .fixedSize(horizontal: true, vertical: false)
        .modifier(GlassSurface(radius: DS.controlRadius, tint: prominent ? DS.accent : nil, interactive: true))
        .contentShape(RoundedRectangle(cornerRadius: DS.controlRadius))
    }

    private func submit() {
        state.capture(then: complete)
        if state.error == .invalidAddress { addressFocused = true }
    }

    @ViewBuilder private var sourceStatus: some View {
        if state.isCapturing {
            HStack(spacing: DS.sm) {
                ProgressView().controlSize(.small).accessibilityHidden(true)
                Text("Rendering the webpage…")
            }
            .font(DS.caption).foregroundStyle(.secondary)
            .transition(DS.Motion.reveal(from: .top, reduceMotion: reduceMotion))
        } else if let error = state.errorMessage {
            VStack(alignment: .leading, spacing: DS.xs) {
                Label { Text(error) } icon: { Icon("warning-circle", size: DS.icon) }
                    .foregroundStyle(.primary)
                if state.error == .pageTooLarge {
                    Button("Use Visible Area") { state.scope = .viewport }
                        .buttonStyle(QuietButtonStyle())
                }
            }
            .font(DS.caption)
            .fixedSize(horizontal: false, vertical: true)
            .transition(DS.Motion.reveal(from: .top, reduceMotion: reduceMotion))
        } else {
            Label {
                if let browser = state.browserName {
                    Text("Uses a temporary profile in \(browser).")
                } else {
                    Text("Requires Chrome, Chromium, Edge, or Brave.")
                }
            } icon: {
                Icon("shield-check", size: DS.icon)
            }
            .font(DS.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var viewport: some View {
        VStack(alignment: .leading, spacing: DS.sm) {
            HStack {
                Text("Viewport size").font(DS.emphasis)
                Spacer()
                if let size = state.breakpoint.size {
                    Text("\(size.width.formatted()) × \(size.height.formatted()) px")
                        .font(DS.mono).foregroundStyle(.secondary)
                        .accessibilityLabel("\(size.width) by \(size.height) pixels")
                }
            }
            options("Viewport preset", URLCapturePanelState.Breakpoint.allCases, selection: $state.breakpoint, label: \.rawValue)
            if state.breakpoint == .custom {
                HStack(spacing: DS.md) {
                    dimensionField("Width", value: $state.customWidth)
                    dimensionField("Height", value: $state.customHeight)
                }
                .transition(DS.Motion.reveal(from: .top, reduceMotion: reduceMotion))
            }
        }
    }

    private var captureScope: some View {
        VStack(alignment: .leading, spacing: DS.sm) {
            Text("Capture scope").font(DS.emphasis)
            options("Capture scope", URLCaptureRequest.Scope.allCases, selection: $state.scope) { scope in
                scope == .fullPage ? "Full Page" : "Visible Area"
            }
        }
    }

    private var pageAppearance: some View {
        VStack(alignment: .leading, spacing: DS.sm) {
            Text("Page appearance").font(DS.emphasis)
            options("Page appearance", URLCaptureRequest.Appearance.allCases, selection: $state.appearance) {
                $0.rawValue.capitalized
            }
        }
    }

    private func dimensionField(_ name: String, value: Binding<String>) -> some View {
        HStack(spacing: DS.xs) {
            Text(name).font(DS.caption).foregroundStyle(.secondary)
            TextField(name, text: value)
                .font(DS.mono).textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel("\(name) in pixels")
            Text("px").font(DS.mono).foregroundStyle(.secondary).accessibilityHidden(true)
        }
        .padding(.horizontal, DS.sm)
        .frame(height: DS.toolButton)
        .background(DS.card(scheme), in: RoundedRectangle(cornerRadius: DS.controlRadius))
        .overlay(RoundedRectangle(cornerRadius: DS.controlRadius).strokeBorder(DS.hairline(scheme)))
    }

    private func options<Value: Hashable>(_ name: String, _ values: [Value], selection: Binding<Value>,
                                          label: @escaping (Value) -> String) -> some View {
        HStack(spacing: DS.xs) {
            ForEach(values, id: \.self) { value in
                let selected = value == selection.wrappedValue
                Button {
                    withAnimation(DS.Motion.snappy(reduceMotion)) { selection.wrappedValue = value }
                } label: {
                    Text(label(value))
                        .font(selected ? DS.emphasis : DS.body)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .foregroundStyle(selected ? DS.actionInk(scheme) : Color.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: DS.toolButton)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: DS.controlRadius)
                                    .fill(DS.accent.opacity(DS.subtleOpacity))
                                    .strokeBorder(DS.actionInk(scheme).opacity(DS.outlineOpacity * 2))
                                    .matchedGeometryEffect(id: name, in: selectionMotion)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(DS.xs)
        .background(DS.card(scheme), in: RoundedRectangle(cornerRadius: DS.smallRadius))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(name)
    }
}
