import Foundation
import Testing
import DesignSystem

struct PinPlacementTests {
    @Test func draggingPreservesTheGrabOffsetWhenCrossingDisplays() {
        let start = CGRect(x: 200, y: 80, width: 320, height: 180)
        let drag = PinGeometry.Drag(frame: start, pointer: CGPoint(x: 295, y: 105), edges: [])
        let result = drag.frame(at: CGPoint(x: -520, y: 380), available: CGSize(width: 1440, height: 900))
        #expect(result == CGRect(x: -615, y: 355, width: 320, height: 180))
    }

    @Test func draggingAnEdgeResizesOnlyTheChosenEdge() {
        let start = CGRect(x: -600, y: 80, width: 300, height: 200)
        let drag = PinGeometry.Drag(frame: start, pointer: CGPoint(x: -301, y: 190), edges: .right)
        let result = drag.frame(at: CGPoint(x: -151, y: 190), available: CGSize(width: 1440, height: 900))
        #expect(result == CGRect(x: -600, y: 30, width: 450, height: 300))
    }

    @Test func placementKeepsVisiblePinsAndRecoversAnOffScreenPin() {
        let displays = [CGRect(x: -1280, y: 100, width: 1280, height: 800), CGRect(x: 0, y: 0, width: 1440, height: 900)]
        let partial = CGRect(x: -1300, y: 220, width: 160, height: 90)
        #expect(PinGeometry.reachable(partial, on: displays) == partial)
        let lost = CGRect(x: -1800, y: 180, width: 160, height: 90)
        let recovered = PinGeometry.reachable(lost, on: displays)
        #expect(recovered.size == lost.size)
        #expect(recovered.intersection(displays[0]).width >= 24)
        #expect(recovered.intersection(displays[0]).height >= 24)
    }
}
