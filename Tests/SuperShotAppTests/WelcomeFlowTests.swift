import CoreGraphics
import Testing
import Capture
@testable import SuperShotApp

struct WelcomeFlowTests {
    @Test func stepsCanBeNavigatedWithoutScreenAccess() {
        #expect(WelcomeStep.intro.previous == nil)
        #expect(WelcomeStep.intro.next == .practice)
        #expect(WelcomeStep.practice.previous == .intro)
        #expect(WelcomeStep.practice.next == .access)
        #expect(WelcomeStep.access.previous == .practice)
        #expect(WelcomeStep.access.next == nil)
    }

    @Test func practiceSelectionHandlesReverseAndOutOfBoundsDrags() {
        let size = CGSize(width: 300, height: 200)
        let start = CGPoint(x: 60, y: 20)
        let end = CGPoint(x: 180, y: 120)
        let expected = CGRect(x: 0.2, y: 0.1, width: 0.4, height: 0.5)

        #expect(WelcomeSelection.normalized(from: start, to: end, in: size, minimum: 8) == expected)
        #expect(WelcomeSelection.normalized(from: end, to: start, in: size, minimum: 8) == expected)
        #expect(WelcomeSelection.normalized(from: CGPoint(x: -10, y: -10), to: CGPoint(x: 900, y: 500),
                                            in: size, minimum: 8) == CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    @Test func practiceIgnoresTinyDragsAndEmptyCanvases() {
        let size = CGSize(width: 300, height: 200)
        #expect(WelcomeSelection.normalized(from: .zero, to: CGPoint(x: 5, y: 120), in: size, minimum: 8) == nil)
        #expect(WelcomeSelection.normalized(from: .zero, to: CGPoint(x: 20, y: 20), in: .zero, minimum: 8) == nil)
    }

    @MainActor @Test func firstPermissionRequestDoesNotStartCaptureWhenAccessIsGranted() {
        var granted = false
        var effects: [String] = []
        let permission = ScreenPermission(check: { granted }, request: {
            effects.append("request")
            granted = true
            return true
        })

        WelcomeAccessAction(permission).perform(permission: permission, openPrivacy: { effects.append("settings") },
                                                finish: { effects.append("finish") }, capture: { effects.append("capture") })

        #expect(effects == ["request"])
        #expect(WelcomeAccessAction(permission) == .capture)
    }

    @MainActor @Test func permissionRecoveryOpensSystemSettingsAfterTheFirstRequest() {
        var effects: [String] = []
        let permission = ScreenPermission(check: { false }, request: { effects.append("request"); return false })
        permission.requestAccess()

        WelcomeAccessAction(permission).perform(permission: permission, openPrivacy: { effects.append("settings") },
                                                finish: { effects.append("finish") }, capture: { effects.append("capture") })

        #expect(effects == ["request", "settings"])
    }

    @MainActor @Test func permissionChangesNeverTurnTheVisibleButtonIntoAnUnchosenAction() {
        var granted = false
        var effects: [String] = []
        let permission = ScreenPermission(check: { granted }, request: { effects.append("request"); return false })
        let request = WelcomeAccessAction(permission)
        granted = true
        request.perform(permission: permission, openPrivacy: { effects.append("settings") },
                        finish: { effects.append("finish") }, capture: { effects.append("capture") })

        let capture = WelcomeAccessAction(permission)
        granted = false
        capture.perform(permission: permission, openPrivacy: { effects.append("settings") },
                        finish: { effects.append("finish") }, capture: { effects.append("capture") })
        #expect(effects.isEmpty)
    }

    @MainActor @Test func explicitCaptureClosesSetupBeforeStartingSelection() {
        var effects: [String] = []
        let permission = ScreenPermission(check: { true }, request: { effects.append("request"); return false })

        WelcomeAccessAction(permission).perform(permission: permission, openPrivacy: { effects.append("settings") },
                                                finish: { effects.append("finish") }, capture: { effects.append("capture") })

        #expect(effects == ["finish", "capture"])
    }
}
