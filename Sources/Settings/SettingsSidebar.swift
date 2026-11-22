import DesignSystem
import SwiftUI

private typealias S = DS.Preferences

struct SettingsSidebar: View {
    typealias Section = SettingsView.Section

    static let navigationGroups: [(title: String, pages: [Section])] = [
        ("App", [.general, .appearance, .shortcuts]),
        ("Workflow", [.capture, .floating, .output, .library]),
        ("Privacy & Ask", [.privacy, .assistant])
    ]
    static let quickPages: [(title: String, section: Section)] = [
        ("Capture", .capture), ("Look", .appearance), ("Output", .output),
        ("Pins", .floating), ("Library", .library), ("Ask", .assistant)
    ]

    @Binding var section: Section
    @Binding var collapsed: Bool
    let short: Bool
    let hasScreenAccess: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.settingsSidebarPreview) private var preview
    @FocusState private var searchFocused: Bool
    @LocalState private var searchVisible = false
    @LocalState private var search = ""
    @Namespace private var selection

    var body: some View {
        VStack(alignment: .leading, spacing: DS.sm) {
            header
            if searchVisible && !collapsed {
                searchField.transition(DS.Motion.reveal(from: .top, reduceMotion: reduceMotion))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: DS.sm) {
                    if !collapsed && !searchVisible { quickDestinations }
                    navigation
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, DS.xs)
            }
            .scrollIndicators(.hidden)
            footer
        }
        .padding(.horizontal, collapsed ? DS.xs : S.railInset)
        .padding(.top, collapsed ? S.railTitlebarHeight : DS.xs)
        .padding(.bottom, DS.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(S.sidebarInk)
        .animation(DS.Motion.panel(reduceMotion), value: section)
        .animation(DS.Motion.snappy(reduceMotion), value: searchVisible)
        .animation(DS.Motion.gentle(reduceMotion), value: matchedSections)
        .onAppear {
            if let query = preview.query {
                search = query
                searchVisible = true
            }
        }
        .onChange(of: section) { _, _ in
            if searchVisible { dismissSearch() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings navigation")
    }

    private var header: some View {
        HStack {
            if !collapsed { Spacer(minLength: 0) }
            Button {
                dismissSearch()
                withAnimation(DS.Motion.panel(reduceMotion)) { collapsed.toggle() }
            } label: {
                Icon("sidebar-simple", size: DS.lg)
                    .foregroundStyle(S.sidebarSecondary)
                    .frame(width: DS.toolButton, height: DS.toolButton)
            }
            .buttonStyle(SettingsButtonStyle(kind: .sidebar))
            .accessibilityLabel(collapsed ? "Show Settings sidebar" : "Hide Settings sidebar")
            .help(collapsed ? "Show Settings sidebar" : "Hide Settings sidebar")
        }
        .frame(maxWidth: .infinity, alignment: collapsed ? .center : .leading)
        .frame(height: collapsed ? S.navigationHeight : S.railTitlebarHeight - DS.xs)
    }

    private var quickDestinations: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.xs), count: 3), spacing: DS.xs) {
            ForEach(Self.quickPages, id: \.section) { destination in
                let selected = destination.section == section
                Button { select(destination.section) } label: {
                    Icon(destination.section.icon, size: DS.iconSize)
                    .foregroundStyle(S.sidebarInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: short ? S.navigationHeight : S.navigationTileHeight)
                    .background(selected ? S.sidebarSelection : S.sidebarTile,
                                in: RoundedRectangle(cornerRadius: S.navigationRowRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: S.navigationRowRadius)
                            .strokeBorder(S.sidebarDivider, lineWidth: S.hairline)
                            .allowsHitTesting(false)
                    }
                }
                .buttonStyle(SettingsButtonStyle(kind: .sidebar))
                .accessibilityLabel("Open \(destination.section.rawValue) settings")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .help(destination.title)
            }
        }
        .padding(.bottom, short ? DS.xs : DS.md)
        .transition(DS.Motion.reveal(from: .top, reduceMotion: reduceMotion))
    }

    private var navigation: some View {
        VStack(alignment: .leading, spacing: DS.sm) {
            ForEach(Self.navigationGroups, id: \.title) { group in
                let pages = group.pages.filter(matchedSections.contains)
                if !pages.isEmpty {
                    VStack(alignment: .leading, spacing: DS.xs / 2) {
                        if !collapsed {
                            if group.title != Self.navigationGroups.first?.title { railDivider.padding(.bottom, DS.sm) }
                            Text(group.title)
                                .font(S.sidebarHeading).foregroundStyle(S.sidebarSecondary)
                                .padding(.horizontal, DS.sm).padding(.bottom, DS.xs)
                                .accessibilityAddTraits(.isHeader)
                        }
                        ForEach(pages, id: \.self) { item in
                            navigationButton(item)
                        }
                    }
                }
            }
            if matchedSections.isEmpty {
                Text("No matching settings").font(S.detail)
                    .foregroundStyle(S.sidebarSecondary)
                    .padding(DS.sm)
            }
        }
    }

    private func navigationButton(_ item: Section) -> some View {
        let selected = item == section
        return Button { select(item) } label: {
            HStack(spacing: DS.sm) {
                Icon(item.icon, size: DS.lg)
                    .frame(width: S.tile)
                    .accessibilityHidden(true)
                if !collapsed {
                    Text(item.rawValue).font(S.sidebarLabel)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: collapsed ? .center : .leading)
            .padding(.horizontal, collapsed ? 0 : DS.xs)
            .frame(height: short ? S.controlHeight : S.navigationHeight)
            .foregroundStyle(selected ? S.sidebarInk : S.sidebarSecondary)
            .background {
                if selected {
                    let shape = RoundedRectangle(cornerRadius: S.navigationRowRadius)
                    let indicator = shape.fill(S.sidebarSelection)
                        .overlay(shape.strokeBorder(S.sidebarDivider, lineWidth: S.hairline))
                        .allowsHitTesting(false)
                    if reduceMotion { indicator.transition(.opacity) }
                    else { indicator.matchedGeometryEffect(id: "section", in: selection) }
                }
            }
        }
        .buttonStyle(SettingsButtonStyle(kind: .sidebar))
        .accessibilityLabel(item.rawValue)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(item.rawValue)
    }

    private var footer: some View {
        let layout = collapsed ? AnyLayout(VStackLayout(spacing: DS.xs)) : AnyLayout(HStackLayout(spacing: DS.xs))
        return layout {
            Button { select(.privacy) } label: {
                HStack(spacing: DS.xs) {
                    Icon(hasScreenAccess ? "shield-check" : "shield-warning", size: DS.lg)
                        .frame(width: DS.toolButton, height: DS.toolButton)
                    if !collapsed { Icon("caret-down", size: DS.sm + DS.xs) }
                }
                .foregroundStyle(S.sidebarSecondary)
            }
            .buttonStyle(SettingsButtonStyle(kind: .sidebar))
            .accessibilityLabel(hasScreenAccess ? "Screen access on, open Privacy settings" : "Screen access off, open Privacy settings")
            .help(hasScreenAccess ? "Screen access on" : "Screen access off")
            if !collapsed { Spacer(minLength: 0) }
            Button(action: revealSearch) {
                Icon("magnifying-glass", size: DS.lg)
                    .foregroundStyle(S.sidebarSecondary)
                    .frame(width: DS.toolButton, height: DS.toolButton)
            }
            .buttonStyle(SettingsButtonStyle(kind: .sidebar))
            .keyboardShortcut("f", modifiers: .command)
            .accessibilityLabel("Find settings")
            .help("Find settings (⌘F)")
        }
        .foregroundStyle(S.sidebarSecondary)
        .frame(maxWidth: .infinity, alignment: collapsed ? .center : .leading)
    }

    private var searchField: some View {
        HStack(spacing: DS.xs) {
            TextField("Find a setting", text: $search, prompt: Text("Find a setting").foregroundStyle(S.sidebarSecondary))
                .font(S.label).foregroundStyle(S.sidebarInk).textFieldStyle(.plain).focused($searchFocused)
                .focusEffectDisabled()
                .accessibilityLabel("Find a setting")
                .onSubmit { if let first = matchedSections.first { select(first) } }
            Button(action: dismissSearch) { Icon("x-circle", size: DS.lg).foregroundStyle(S.sidebarSecondary) }
                .buttonStyle(SettingsButtonStyle(kind: .sidebar))
                .accessibilityLabel("Close search")
        }
        .padding(.horizontal, DS.sm).frame(height: S.navigationHeight)
        .background(S.sidebarTile, in: RoundedRectangle(cornerRadius: S.controlRadius))
        .overlay {
            RoundedRectangle(cornerRadius: S.controlRadius).strokeBorder(
                searchFocused ? S.sidebarFocus : S.sidebarDivider, lineWidth: searchFocused ? S.focusWidth : S.hairline
            ).allowsHitTesting(false)
        }
        .onAppear { if !DS.rendersOffscreen { searchFocused = true } }
        .onExitCommand(perform: dismissSearch)
    }

    private var railDivider: some View {
        Rectangle().fill(S.sidebarDivider).frame(height: S.hairline)
            .padding(.horizontal, -S.railInset)
            .accessibilityHidden(true)
    }

    private var matchedSections: [Section] { Self.matches(search) }

    static func matches(_ search: String) -> [Section] {
        let terms = search.split(whereSeparator: \.isWhitespace)
        return navigationGroups.flatMap(\.pages).filter { item in
            let text = item.rawValue + " " + item.searchTerms
            return terms.allSatisfy { text.localizedCaseInsensitiveContains(String($0)) }
        }
    }

    private func select(_ item: Section) {
        section = item
        dismissSearch()
    }

    private func dismissSearch() {
        search = ""
        searchFocused = false
        searchVisible = false
    }

    private func revealSearch() {
        withAnimation(DS.Motion.panel(reduceMotion)) { collapsed = false }
        searchVisible = true
        searchFocused = true
    }

}

struct SettingsRailSurface: View {
    let solid: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: S.navigationRadius)
        let glass = !DS.usesOpaqueChrome(reduceTransparency: solid)
        ZStack {
            if glass {
                Color.clear.modifier(GlassSurface(radius: S.navigationRadius,
                                                  backing: S.sidebarTint(scheme).opacity(0.82)))
            } else {
                shape.fill(S.sidebarFallback(scheme))
            }
            if !solid, ThemeState.shared.chrome == .glass {
                shape.fill(LinearGradient(stops: [
                    .init(color: S.sidebarReflection, location: 0),
                    .init(color: .clear, location: 0.32),
                    .init(color: S.sidebarReflection, location: 0.54),
                    .init(color: .clear, location: 0.90)
                ], startPoint: .topTrailing, endPoint: .bottomLeading))
                shape.strokeBorder(S.sidebarDivider, lineWidth: S.hairline)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private extension SettingsView.Section {
    var searchTerms: String {
        switch self {
        case .general: "login startup dock"
        case .appearance: "theme dark light system accent density compact glass solid chrome toolbar editor tools area overlay labels thumbnail buttons"
        case .assistant: "ask chatgpt codex claude provider model account sign in out privacy redact text conversations suggestions"
        case .capture: "area window screen scrolling webpage recording video audio camera auto automatic copy clipboard save editor shadow cursor pointer icons sound tint opacity backdrop actions enter return confirm release skip instant"
        case .output: "png jpeg heic pdf tiff webp avif format quality resolution retina color srgb file name folder location editable linked exports"
        case .floating: "thumbnail corner position dismiss timer size pin opacity transparency shadow spaces move resize unlock click through"
        case .shortcuts: "keyboard hotkeys bindings profiles keys tools import export"
        case .library: "history retention days storage search organize metadata titles tags summaries"
        case .privacy: "permission recording access screen local privacy review links share microphone camera"
        }
    }
}
