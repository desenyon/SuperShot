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

    var body: some View {
        VStack(alignment: .leading, spacing: DS.xl) {
            HStack(spacing: DS.sm) {
                Image(systemName: "viewfinder").foregroundStyle(.secondary)
                Text("SuperShot").font(DS.emphasis)
                Spacer()
                Text("Setup").font(DS.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: DS.sm) {
                Text(ready ? "Ready when you are" : "Allow screen access").font(DS.title)
                Text(ready ? "Capture from the menu bar or use a shortcut. This setup won’t appear on your next launch." : "Allow SuperShot in Screen & System Audio Recording to capture a screen, window, or area.")
                    .font(DS.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: DS.lg) {
                HStack {
                    Text("Screen Recording").font(DS.body)
                    Spacer()
                    Image(systemName: ready ? "checkmark.circle.fill" : "lock").foregroundStyle(ready ? DS.success : Color.secondary)
                    Text(ready ? "Allowed" : "Required").font(DS.caption).foregroundStyle(.secondary)
                }
                Hairline()
                HStack {
                    Text("Capture an area").font(DS.body)
                    Spacer()
                    Text(settings.preferences.shortcuts["area"]?.display ?? "Menu bar → Capture Area").font(DS.mono).foregroundStyle(.secondary)
                }
            }.padding(DS.lg).background(DS.settingsGroup(scheme), in: RoundedRectangle(cornerRadius: DS.groupRadius))
            Spacer(minLength: 0)
            HStack {
                Button(ready ? "Settings" : "Later", action: ready ? openSettings : finish).buttonStyle(QuietButtonStyle())
                Spacer()
                if ready {
                    Button("Done", action: finish).buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                } else {
                    Button(permission.hasRequested ? "Open System Settings" : "Allow screen access") {
                        if permission.hasRequested { openPrivacy() } else { permission.requestAccess() }
                    }.buttonStyle(PrimaryButtonStyle())
                }
            }
        }
        .padding(DS.xl).padding(.top, DS.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.settingsBackground(scheme)).ignoresSafeArea()
        .task {
            while !Task.isCancelled {
                permission.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
