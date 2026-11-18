import Testing
@testable import Capture

@MainActor struct OverlayActionTests {
    @Test func customBarKeepsOrderAndAlwaysHasCapture() {
        #expect(SelectionView.orderedActions([.ask, .save, .ask]) == [.capture, .ask, .save])
        #expect(SelectionView.orderedActions([.edit, .capture, .copy]) == [.edit, .capture, .copy])
        #expect(SelectionView.orderedActions([]) == [.capture])
    }
}
