import CoreGraphics
import Observation

public enum ScreenPermissionState: Equatable, Sendable { case needsAccess, authorized }

/// Only the OS probe establishes authorization; a clicked button never does.
@MainActor @Observable public final class ScreenPermission {
    public private(set) var state: ScreenPermissionState
    public private(set) var hasRequested = false
    @ObservationIgnored private let check: () -> Bool
    @ObservationIgnored private let request: () -> Bool

    public init(check: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() },
                request: @escaping () -> Bool = { CGRequestScreenCaptureAccess() }) {
        self.check = check
        self.request = request
        state = check() ? .authorized : .needsAccess
    }
    public func refresh() { state = check() ? .authorized : .needsAccess }
    public func requestAccess() {
        refresh()
        guard state != .authorized else { return }
        hasRequested = true
        _ = request()
        refresh()
    }
}
