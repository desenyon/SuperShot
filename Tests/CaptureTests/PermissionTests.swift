import Testing
import Foundation
@testable import Capture

final class PermissionTests {
    @Test @MainActor func testDeniedRequestDoesNotPretendToGrant() {
        let permission = ScreenPermission(check: { false }, request: { false })
        permission.requestAccess()
        #expect(permission.state == .needsAccess)
        #expect(permission.hasRequested)
    }
    @Test @MainActor func testRefreshDetectsGrantAndRevocation() {
        var allowed = false
        let permission = ScreenPermission(check: { allowed }, request: { false })
        #expect(permission.state == .needsAccess)
        allowed = true
        permission.refresh()
        #expect(permission.state == .authorized)
        allowed = false
        permission.refresh()
        #expect(permission.state == .needsAccess)
    }
    @Test @MainActor func testExistingAccessDoesNotPromptAgain() {
        var prompts = 0
        let permission = ScreenPermission(check: { true }, request: { prompts += 1; return true })
        permission.requestAccess()
        #expect(prompts == 0)
    }
}
