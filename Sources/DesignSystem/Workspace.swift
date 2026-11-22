import SwiftUI

/// The neutral content plane shared by utility windows and capture workspaces.
public struct WorkspaceBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init() {}

    public var body: some View {
        DS.Preferences.canvas(scheme)
            .overlay {
                if !DS.usesOpaqueChrome(reduceTransparency: reduceTransparency) {
                    Rectangle().fill(.ultraThinMaterial).opacity(DS.subtleOpacity)
                }
            }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

public struct WorkspaceHeader: View {
    private let title: String
    private let subtitle: String?
    private let icon: String

    public init(title: String, subtitle: String? = nil, icon: String) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DS.xs) {
            HStack(spacing: DS.sm) {
                Icon(icon, size: DS.iconSize).foregroundStyle(.secondary).accessibilityHidden(true)
                Text(title).font(DS.title.weight(.medium)).accessibilityAddTraits(.isHeader)
            }
            if let subtitle {
                Text(subtitle).font(DS.body).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
