import Capture

/// Keeps each explicit button action tied to the permission state the user saw.
enum WelcomeAccessAction: Equatable {
    case requestAccess, openSystemSettings, capture

    @MainActor init(_ permission: ScreenPermission) {
        if permission.state == .authorized { self = .capture }
        else { self = permission.hasRequested ? .openSystemSettings : .requestAccess }
    }

    var label: String {
        switch self {
        case .requestAccess: "Allow screen access"
        case .openSystemSettings: "Open System Settings"
        case .capture: "Capture an area"
        }
    }

    @MainActor func perform(permission: ScreenPermission, openPrivacy: () -> Void,
                            finish: () -> Void, capture: () -> Void) {
        permission.refresh()
        guard self == Self(permission) else { return }
        switch self {
        case .requestAccess: permission.requestAccess()
        case .openSystemSettings: openPrivacy()
        case .capture:
            finish()
            capture()
        }
    }
}
