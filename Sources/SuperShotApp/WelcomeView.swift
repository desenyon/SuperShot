import SwiftUI
import DesignSystem
import Settings
import Capture

/// A one-time permission setup. Capture commands live in the menu bar.
struct WelcomeView: View {
    @Environment(\.colorScheme) private var scheme
    @Bindable var settings: SettingsStore
    let permission: ScreenPermission
    let capture: (String) -> Void
    let openSettings: () -> Void
    let openPrivacy: () -> Void
    let finish: () -> Void
    private var ready: Bool { permission.state == .authorized }

    private typealias S = DS.Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: DS.lg) {
            HStack(spacing: DS.md) {
                BrandMark(size: DS.xxl).padding(DS.lg).grayscale(1).drawingGroup().padding(-DS.lg)
                Text("SuperShot").font(DS.emphasis)
            }.staggeredAppear(0)
            VStack(alignment: .leading, spacing: DS.sm) {
                Text(ready ? "Ready to capture" : "Allow screen access").font(S.title)
                    .accessibilityAddTraits(.isHeader)
                Text(ready ? "Use the menu bar or a keyboard shortcut to take your first screenshot." :
                        "Allow SuperShot in Screen & System Audio Recording to capture a screen, window, or area.")
                    .font(S.label).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.staggeredAppear(1)
            VStack(spacing: 0) {
                HStack(spacing: DS.sm) {
                    Icon(ready ? "shield-check" : "shield-warning", size: DS.lg)
                    Text("Screen Recording")
                    Spacer()
                    Text(ready ? "Allowed" : "Required").foregroundStyle(.secondary)
                }.frame(minHeight: S.rowHeight)
                Rectangle().fill(S.edge(scheme)).frame(height: S.hairline)
                HStack(spacing: DS.sm) {
                    Icon("frame-corners", size: DS.lg)
                    Text("Capture an area")
                    Spacer()
                    Text(settings.preferences.shortcuts["area"]?.display ?? "Menu bar → Capture Area")
                        .font(S.mono).padding(.horizontal, DS.sm).frame(height: S.controlHeight)
                        .background(S.fill(scheme), in: RoundedRectangle(cornerRadius: S.controlRadius))
                }.frame(minHeight: S.rowHeight)
            }
            .font(S.label).padding(.horizontal, DS.md).padding(.vertical, DS.xs)
            .background(S.groupFallback(scheme), in: RoundedRectangle(cornerRadius: S.radius))
            .overlay(RoundedRectangle(cornerRadius: S.radius).strokeBorder(S.edge(scheme), lineWidth: S.hairline))
            .shadow(color: S.cardShadow(scheme), radius: DS.xs / 2, y: DS.stroke)
            .staggeredAppear(2)
            Spacer(minLength: 0)
            HStack {
                Button(ready ? "Settings" : "Later", action: ready ? openSettings : finish)
                    .setupButton()
                Spacer()
                Button(ready ? "Done" : permission.hasRequested ? "Open System Settings" : "Allow screen access") {
                    if ready { finish() }
                    else if permission.hasRequested { openPrivacy() }
                    else { permission.requestAccess() }
                }.setupButton(primary: true).keyboardShortcut(.defaultAction)
            }.staggeredAppear(3)
        }
        .padding(DS.xl).padding(.top, DS.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(S.canvas(scheme)).ignoresSafeArea()
        .task {
            while !Task.isCancelled {
                permission.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
