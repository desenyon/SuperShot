import Testing
@testable import AI

struct CaptureOrganizerTests {
    @Test func textAndVisionFallbackYieldsBoundedSearchableMetadata() {
        let result = CaptureOrganizer.suggestion(from: "   UI\n  Project review notes   \n Confirm the timeline ",
                                                 source: "Safari", labels: ["document", "safari", "office_supply"])
        #expect(result.title == "Project review notes")
        #expect(result.tags == ["Safari", "document", "office supply"])
        #expect(result.summary?.contains("Confirm the timeline") == true)
        let empty = CaptureOrganizer.suggestion(from: " \n", source: "Screenshot", labels: [])
        #expect(empty.title == nil && empty.summary == nil && empty.tags == ["Screenshot"])
    }
}
