import AI
import AppKit
import CoreGraphics
import Document
import Export
import Foundation
import Recognition
import Render
import Synchronization
import Testing
@testable import Editor

/// Tests control stream delivery explicitly, including late events after Stop.
private final class ScriptedSession: AssistantConversation, Sendable {
    typealias Stream = AsyncThrowingStream<AssistantEvent, Error>
    struct State {
        var prompts: [String] = []
        var attachments: [AssistantAttachment] = []
        var contexts: [AssistantContext] = []
        var continuation: Stream.Continuation?
        var cancelled = false
        var closed = false
    }
    let state = Mutex(State())
    func send(_ text: String, attachments: [AssistantAttachment]) -> Stream {
        let (stream, continuation) = Stream.makeStream()
        state.withLock {
            $0.prompts.append(text); $0.attachments = attachments; $0.continuation = continuation
        }
        return stream
    }
    func cancel() async { state.withLock { $0.cancelled = true; $0.continuation?.finish() } }
    func close() async { state.withLock { $0.closed = true; $0.continuation?.finish() } }
    func yield(_ event: AssistantEvent) { _ = state.withLock { $0.continuation?.yield(event) } }
    func fail(_ error: AssistantError) { state.withLock { $0.continuation?.finish(throwing: error) } }
}

private struct ScriptedAssistant: AssistantService {
    let provider: AssistantProvider
    let session: ScriptedSession
    func availability() async -> AssistantAvailability { .ready(.init(toolVersion: "test", toolPath: "fixture")) }
    func signIn() async throws -> AssistantSignIn { throw AssistantError.tool("Unexpected login") }
    func signOut() async throws {}
    func usage() async -> AssistantUsage? { nil }
    func models() async -> [String] { [] }
    func startConversation(_ context: AssistantContext, model: String?) async throws -> any AssistantConversation {
        session.state.withLock { $0.contexts.append(context) }
        return session
    }
}

@MainActor struct AskModelTests {
    private func fixture() throws -> CaptureDocument {
        let ctx = try #require(CGContext(data: nil, width: 96, height: 72, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(gray: 1, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 96, height: 72))
        let image = try #require(ctx.makeImage())
        return CaptureDocument(original: try ImageExport.encode(image), width: 96, height: 72, source: "Fieldnotes — Workspace")
    }
    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try #require(condition())
    }
    private func make(_ session: ScriptedSession, consent: Bool = false) async -> AskModel {
        let model = AskModel(options: AskOptions(confirmBeforeSending: consent, includeRecognizedText: false),
                             factory: { ScriptedAssistant(provider: $0, session: session) })
        await model.refreshAvailability()
        return model
    }

    @Test func consentGatesContextAndCropsRenderedRegion() async throws {
        var doc = try fixture()
        doc.backdrop.fill = .solid; doc.backdrop.padding = 10; doc.crop = CGRect(x: 4, y: 6, width: 64, height: 44)
        let session = ScriptedSession(), model = await make(session, consent: true)
        model.attach(CGRect(x: 6, y: 8, width: 24, height: 10), in: doc)
        model.draft = "What is selected?"; model.send(document: doc)
        #expect(model.awaitingConsent)
        #expect(session.state.withLock { $0.contexts.isEmpty && $0.prompts.isEmpty })
        model.cancelConsent()
        #expect(model.messages.isEmpty && model.regions.count == 1 && model.draft == "What is selected?")
        model.send(document: doc); model.confirm(redact: false)
        try await wait { session.state.withLock { $0.prompts.count == 1 } }
        let context = try #require(session.state.withLock { $0.contexts.first })
        #expect(context.image.width == 84 && context.image.height == 64)
        #expect(context.appName == "Fieldnotes" && context.windowTitle == "Workspace" && context.recognizedText == nil)
        #expect(session.state.withLock { $0.attachments.first?.image.width == 24 && $0.attachments.first?.image.height == 10 })
        session.yield(.delta("First ")); session.yield(.delta("reply")); session.yield(.usage(.init(usedFraction: 0.2))); session.yield(.done)
        try await wait { !model.isSending }
        #expect(model.messages.last?.text == "First reply" && model.usage?.usedFraction == 0.2)
        model.draft = "Again"; model.send(document: doc)
        try await wait { session.state.withLock { $0.prompts.count == 2 } }
        #expect(session.state.withLock { $0.contexts.count == 1 })
        model.stop()
    }

    @Test func stopKeepsPartialReplyAndDiscardsLateDeltas() async throws {
        let session = ScriptedSession(), model = await make(session)
        model.draft = "Start"; model.send(document: try fixture())
        try await wait { session.state.withLock { $0.prompts.count == 1 } }
        session.yield(.delta("Partial"))
        try await wait { model.messages.last?.text == "Partial" }
        model.stop(); session.yield(.delta("late"))
        try await wait { session.state.withLock { $0.cancelled && $0.closed } }
        #expect(!model.isStreaming && model.messages.last?.text == "Partial" && model.error == nil)
    }

    @Test func editingAfterStopRequiresConsentForTheNewPixels() async throws {
        let document = try fixture()
        let session = ScriptedSession()
        let model = await make(session, consent: true)
        model.draft = "Read this"
        model.send(document: document)
        model.confirm(redact: false)
        try await wait { session.state.withLock { $0.prompts.count == 1 } }
        model.stop()
        try await wait { session.state.withLock { $0.closed } }

        var edited = document
        edited.crop = CGRect(x: 8, y: 4, width: 40, height: 30)
        model.draft = "Read the cropped image"
        model.send(document: edited)
        #expect(model.awaitingConsent)
        #expect(session.state.withLock { $0.contexts.count == 1 && $0.prompts.count == 1 })
        model.confirm(redact: false)
        try await wait { session.state.withLock { $0.prompts.count == 2 } }
        let replacement = try #require(session.state.withLock { $0.contexts.last })
        #expect(replacement.image.width == 40 && replacement.image.height == 30)
        model.stop()
    }

    @Test func pendingConsentAndSelectedRegionFollowCommittedEdits() async throws {
        let document = try fixture()
        let session = ScriptedSession()
        let model = await make(session, consent: true)
        model.attach(CGRect(x: 2, y: 4, width: 24, height: 14), in: document)
        model.draft = "Describe the region"
        model.send(document: document)
        #expect(model.awaitingConsent)

        var edited = document
        edited.crop = CGRect(x: 8, y: 4, width: 18, height: 30)
        model.updateDraft(for: edited)
        #expect(!model.awaitingConsent)
        #expect(model.draft == "Describe the region")
        #expect(model.regions.first?.rect == CGRect(x: 8, y: 4, width: 18, height: 14))
        model.confirm(redact: false)
        #expect(session.state.withLock { $0.contexts.isEmpty })

        model.send(document: edited)
        model.confirm(redact: false)
        try await wait { session.state.withLock { $0.prompts.count == 1 } }
        #expect(session.state.withLock { $0.attachments.first?.image.width == 18 })
        model.stop()
    }

    @Test func switchAfterLimitRequiresConsentAndCarriesEarlierTurns() async throws {
        let first = ScriptedSession(), second = ScriptedSession(), doc = try fixture()
        let model = AskModel(options: AskOptions(includeRecognizedText: false),
                             factory: { ScriptedAssistant(provider: $0, session: $0 == .chatgpt ? first : second) })
        await model.refreshAvailability()
        model.draft = "Read the heading"; model.send(document: doc); model.confirm(redact: false)
        try await wait { first.state.withLock { $0.prompts.count == 1 } }
        first.yield(.delta("Fieldnotes")); first.yield(.done)
        try await wait { !model.isSending }
        model.draft = "What next?"; model.send(document: doc)
        try await wait { first.state.withLock { $0.prompts.count == 2 } }
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        first.fail(.limitReached(resetsAt: date))
        try await wait { model.usage?.limitReached == true }
        #expect(model.usage?.resetsAt == date)
        let visible = model.transcript
        model.switchProvider(.claude)
        try await wait { model.availability?.isReady == true }
        #expect(model.transcript == visible && model.draft == "What next?")
        model.send(document: doc)
        #expect(model.awaitingConsent && second.state.withLock { $0.contexts.isEmpty })
        model.confirm(redact: false)
        try await wait { second.state.withLock { $0.prompts.count == 1 } }
        #expect(second.state.withLock { $0.prompts[0].contains("Fieldnotes") && $0.prompts[0].hasSuffix("What next?") })
        second.yield(.done)
        try await wait { !model.isSending }
    }

    @Test func retryRestoresFailedQuestion() async throws {
        let session = ScriptedSession(), model = await make(session), doc = try fixture()
        model.draft = "Try"; model.send(document: doc)
        try await wait { session.state.withLock { $0.prompts.count == 1 } }
        session.fail(.tool("Tool disconnected"))
        try await wait { model.error == "Tool disconnected" }
        model.retry()
        try await wait { session.state.withLock { $0.prompts.count == 2 } }
        session.yield(.delta("Recovered")); session.yield(.done)
        try await wait { !model.isSending }
        #expect(model.messages.map(\.text) == ["Try", "Recovered"])
        #expect(model.error == nil)
    }

    @Test func redactionCoversImageAndRegionAndFiltersOCR() throws {
        var doc = try fixture()
        doc.source = "Fieldnotes — user@example.test"
        let image = try DocumentRenderer.render(doc)
        let line = TextRegion(text: "user@example.test", rect: CGRect(x: 10, y: 8, width: 45, height: 8))
        let result = RecognitionResult(text: [line, .init(text: "Public", rect: CGRect(x: 10, y: 50, width: 30, height: 10))])
        let capture = AskCapture(document: doc, image: image, recognition: result, candidates: SensitiveContent.candidates(in: result))
        let context = try capture.context(redact: true, includeText: true)
        #expect(context.recognizedText == "Public" && context.windowTitle == "[redacted]" && context.appName == "Fieldnotes")
        let region = try #require(context.image.cropping(to: line.rect))
        #expect(DocumentRenderer.sample(region, at: CGPoint(x: 2, y: 2)).red < 0.05)
        #expect(DocumentRenderer.sample(context.image, at: CGPoint(x: 20, y: 55)).red > 0.95)
        #expect(DocumentRenderer.sample(image, at: CGPoint(x: 20, y: 10)).red > 0.95)
        let thumbnail = try capture.redactedThumbnail(maxDimension: 48)
        let preview = try #require(thumbnail)
        #expect(preview.width == 48 && preview.height == 36)
        #expect(DocumentRenderer.sample(preview, at: CGPoint(x: 10, y: 6)).red < 0.05)
    }

    @Test func regionThumbnailReflectsTheAnchoredCropWithoutSendingAnything() async throws {
        var doc = try fixture()
        doc.crop = CGRect(x: 5, y: 5, width: 70, height: 50)
        doc.backdrop.fill = .solid
        doc.backdrop.padding = 12
        let session = ScriptedSession()
        let model = await make(session)
        model.attach(CGRect(x: 10, y: 12, width: 24, height: 12), in: doc)
        let region = try #require(model.regions.first)
        let thumbnail = await region.thumbnail()
        let preview = try #require(thumbnail)
        #expect(preview.width == 24 && preview.height == 12)
        #expect(DocumentRenderer.sample(preview, at: CGPoint(x: 12, y: 6)).red > 0.95)
        #expect(session.state.withLock { $0.contexts.isEmpty && $0.prompts.isEmpty })
    }
}

extension AskModelTests {
    @Test func askIsLazyAndTextLayerIsUndoable() throws {
        let doc = try fixture(), editor = EditorModel(document: doc)
        #expect(editor.prepareAsk() == nil)
        editor.askOptions = AskOptions()
        editor.assistantFactory = { PreviewAssistantService(provider: $0) }
        #expect(editor.ask == nil)
        let model = try #require(editor.prepareAsk())
        #expect(editor.inspector.isEmpty && editor.openAsk() === model)
        let line = TextRegion(text: "In progress", rect: CGRect(x: 0, y: 0, width: 20, height: 12))
        #expect(model.matchingRegion(in: "The item is marked **In progress**.", document: doc, editorText: [line]) == line.rect)
        editor.addReply("This reply should wrap inside the visible image.")
        let layer = try #require(editor.document.layers.last)
        #expect(layer.kind == .text && doc.visibleBounds.contains(layer.rect))
        #expect(layer.text.contains("\n") && editor.selected == [layer.id])
        editor.undo()
        #expect(editor.document.layers.isEmpty)
    }
}


extension AskModelTests {
    @Test func detachedCanvasAttachesOnceAndEscapeLeavesDocumentAlone() throws {
        let doc = try fixture(), editor = EditorModel(document: doc)
        editor.askOptions = AskOptions()
        editor.assistantFactory = { PreviewAssistantService(provider: $0) }
        let model = try #require(editor.openAsk())
        editor.showBackdrop = false; editor.zoom = 1
        let canvas = CanvasView(model: editor)
        canvas.frame = CGRect(x: 0, y: 0, width: 900, height: 600)
        canvas.sync()
        // The raster lives in the canvas stage; find it at any depth and use canvas coordinates.
        func rasterLayer(in layer: CALayer?) -> CALayer? {
            guard let layer else { return nil }
            if layer.contents != nil { return layer }
            return layer.sublayers?.lazy.compactMap { rasterLayer(in: $0) }.first
        }
        let root = try #require(canvas.layer)
        let raster = try #require(rasterLayer(in: root))
        let frame = raster.superlayer.map { $0.convert(raster.frame, to: root) } ?? raster.frame
        let start = CGPoint(x: frame.midX, y: frame.midY)
        func event(_ type: NSEvent.EventType, dx: CGFloat = 0, dy: CGFloat = 0) throws -> NSEvent {
            let point = canvas.convert(CGPoint(x: start.x + dx, y: start.y + dy), to: nil)
            return try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                                   windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        editor.pickingAskRegion = true
        canvas.mouseDown(with: try event(.leftMouseDown))
        canvas.mouseDragged(with: try event(.leftMouseDragged, dx: 15, dy: 8))
        canvas.mouseUp(with: try event(.leftMouseUp, dx: 16, dy: 9))
        #expect(model.regions.map(\.label) == ["Region 1 · 16 × 9"])
        #expect(!editor.pickingAskRegion && !editor.canUndo)
        editor.pickingAskRegion = true
        canvas.mouseDown(with: try event(.leftMouseDown))
        canvas.mouseDragged(with: try event(.leftMouseDragged, dx: 12, dy: 5))
        let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                   windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                                                   isARepeat: false, keyCode: 53))
        canvas.keyDown(with: escape)
        canvas.mouseUp(with: try event(.leftMouseUp, dx: 12, dy: 5))
        #expect(!editor.pickingAskRegion && model.regions.count == 1 && editor.document == doc)
    }
}

extension AskModelTests {
    @Test func finishedRepliesReachTheTranscriptHookAndClearingEmptiesIt() async throws {
        let doc = try fixture(), session = ScriptedSession(), model = await make(session)
        var reported: [[AskMessage]] = []
        model.onTranscript = { reported.append($0) }
        model.draft = "Summarize"; model.send(document: doc)
        try await wait { session.state.withLock { $0.prompts.count == 1 } }
        session.yield(.delta("Short summary")); session.yield(.done)
        try await wait { !model.isSending }
        #expect(reported.last?.map(\.text) == ["Summarize", "Short summary"])
        model.newConversation()
        #expect(reported.last?.isEmpty == true)
    }
    @Test func restoredConversationIsShownAndCarriedIntoTheNextThread() async throws {
        let doc = try fixture(), session = ScriptedSession()
        let model = AskModel(options: AskOptions(confirmBeforeSending: false, includeRecognizedText: false),
                             factory: { ScriptedAssistant(provider: $0, session: session) },
                             messages: [AskMessage(.user, "Earlier question"), AskMessage(.assistant, "Earlier answer")])
        await model.refreshAvailability()
        #expect(model.messages.count == 2 && model.includesEarlierMessages)
        model.draft = "Follow up"; model.send(document: doc)
        try await wait { session.state.withLock { $0.prompts.count == 1 } }
        #expect(session.state.withLock { $0.prompts.first?.contains("Earlier answer") == true })
    }
}

extension AskModelTests {
    @Test func quickActionsSendTheirPromptAndShowTheirTitle() async throws {
        let doc = try fixture(), session = ScriptedSession(), model = await make(session)
        model.draft = "the login form"
        model.ask(.named("Solve"), document: doc)
        try await wait { session.state.withLock { $0.prompts.count == 1 } }
        let prompt = try #require(session.state.withLock { $0.prompts.first })
        #expect(prompt.hasPrefix(AskQuickAction.named("Solve").prompt) && prompt.hasSuffix("The user added: the login form"))
        let bubble = try #require(model.messages.first)
        #expect(bubble.action?.title == "Solve" && bubble.typed == "the login form" && model.draft.isEmpty)
        #expect(AskQuickAction.builtIn.map(\.title) == ["Solve", "Explain", "Suggest", "Improve"])
        #expect(AskQuickAction.named("explain").icon == "book-open-text")
        let custom = AskQuickAction.named("Write alt text")
        #expect(custom.prompt == "Write alt text" && custom.request(with: "") == "Write alt text")
    }
    @Test func cancellingConsentForAnActionRestoresOnlyWhatWasTyped() async throws {
        let doc = try fixture(), session = ScriptedSession(), model = await make(session, consent: true)
        model.draft = "the chart"
        model.ask(.named("Explain"), document: doc)
        #expect(model.awaitingConsent)
        model.cancelConsent()
        #expect(model.draft == "the chart" && model.messages.isEmpty)
    }
}
