import AI
import AVFoundation
import Capture
import Document
import Editor
import Export
import Foundation
import Render
import Testing
@testable import SuperShotApp

@MainActor
struct RecordingAskTests {
    @Test func usesTheEditedTimelineForTheSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Generated.mp4")
        try await makeMovie(at: url)
        let trim = try #require(RecordingRange(start: 0, end: 2))
        let original = try await RecordingAskFrameInput(sourceURL: url, editedTime: 0.5, edits: RecordingEdits(trim: trim)).render()
        var edits = RecordingEdits(trim: trim)
        edits.cuts = [try #require(RecordingRange(start: 0, end: 1))]
        let editedInput = RecordingAskFrameInput(sourceURL: url, editedTime: 0.5, edits: edits)
        let edited = try await editedInput.render()
        let end = try await RecordingAskFrameInput(sourceURL: url, editedTime: 1, edits: edits).render()
        #expect(edited.document.width == 96 && edited.document.height == 64)
        #expect(abs(edited.time - 0.5) < 0.05)
        #expect(end.time > 0.9 && end.time <= 1)
        #expect(try pixel(edited.document) > pixel(original.document) + 100)

        edits.annotations = [RecordingAnnotation(kind: .cover, range: try #require(RecordingRange(start: 1.25, end: 1.75)),
                                                 start: .zero, end: CGPoint(x: 1, y: 1))]
        let covered = try await RecordingAskFrameInput(sourceURL: url, editedTime: 0.5, edits: edits).render()
        let later = try await RecordingAskFrameInput(sourceURL: url, editedTime: 0.9, edits: edits).render()
        #expect(try pixel(covered.document) < 15)
        #expect(try pixel(later.document) > 150)
    }

    @Test func pendingLoadsNeverReplaceAConversationAfterDisableOrANewerSelection() async throws {
        let loader = LoadGate()
        let session = RecordingAskSession(factory: { PreviewAssistantService(provider: $0) }, load: { try await loader.load($0) })
        session.updateOptions(AskOptions())
        let older = try #require(session.selectFrame(try input(at: 1)))
        try #require(try await loader.received(1))
        let newer = try #require(session.selectFrame(try input(at: 2)))
        try #require(try await loader.received(2))
        await loader.finish(2)
        await newer.value
        let conversation = try #require(session.conversation)
        conversation.model.draft = "Keep this draft"
        await loader.finish(1)
        await older.value
        #expect(session.conversation?.time == 2)
        #expect(session.conversation?.model === conversation.model)
        #expect(session.conversation?.model.draft == "Keep this draft")

        let pending = try #require(session.selectFrame(try input(at: 3)))
        try #require(try await loader.received(3))
        session.updateOptions(nil)
        await loader.finish(3)
        await pending.value
        #expect(session.conversation == nil)
        #expect(!session.isPreparing)
    }

    @Test func failedSelectionKeepsTheOriginalAndReplacementRequiresFreshConsent() async throws {
        let recorder = TurnRecorder()
        let session = RecordingAskSession(factory: { CheckingService(provider: $0, recorder: recorder) }, load: { request in
            guard request.editedTime != 2 else { throw RecordingFailure.invalidRange }
            return try makeSnapshot(at: request.editedTime)
        })
        session.updateOptions(AskOptions())
        await session.selectFrame(try input(at: 1))?.value
        let initial = try #require(session.conversation)
        await initial.model.refreshAvailability()
        #expect(await recorder.started.isEmpty)
        initial.model.draft = "What is on screen?"
        initial.model.attach(CGRect(x: 0, y: 0, width: 1, height: 1), in: initial.editor.current)
        initial.model.send(document: initial.editor.current)
        #expect(initial.model.awaitingConsent)
        #expect(initial.model.messages.last?.attachments.count == 1)
        #expect(await recorder.started.isEmpty)
        initial.model.confirm(redact: false)
        let deadline = ContinuousClock.now + .seconds(15)
        while await recorder.started.isEmpty && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(await recorder.started.count == 1, "First scripted turn did not start. \(initial.model.error ?? "")")

        await session.selectFrame(try input(at: 2))?.value
        #expect(session.error != nil)
        #expect(session.conversation?.model === initial.model)
        await session.selectFrame(try input(at: 3))?.value
        let replacement = try #require(session.conversation)
        #expect(session.error == nil)
        #expect(replacement.model !== initial.model)
        #expect(replacement.model.messages.isEmpty)
        await replacement.model.refreshAvailability()
        replacement.model.draft = "What is in this new frame?"
        replacement.model.send(document: replacement.editor.current)
        #expect(replacement.model.awaitingConsent)
        #expect(await recorder.started.count == 1)
        replacement.model.cancelConsent()
        #expect(replacement.model.draft == "What is in this new frame?")
        session.end()
    }

    private func input(at time: TimeInterval) throws -> RecordingAskFrameInput {
        RecordingAskFrameInput(sourceURL: URL(filePath: "/fixture.mp4"), editedTime: time,
                               edits: RecordingEdits(trim: try #require(RecordingRange(start: 0, end: 5))))
    }

    private func pixel(_ document: CaptureDocument) throws -> Int {
        let image = try #require(DocumentRenderer.decode(document.original))
        let bitmap = try #require(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return Int(try #require(bitmap.data).load(as: UInt8.self))
    }

    nonisolated private func makeMovie(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 96, AVVideoHeightKey: 64,
        ])
        let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 96, kCVPixelBufferHeightKey as String: 64,
        ])
        writer.add(input)
        try #require(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        let pool = try #require(adapter.pixelBufferPool)
        for frame in 0..<60 {
            for _ in 0..<100 where !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            try #require(input.isReadyForMoreMediaData)
            var allocated: CVPixelBuffer?
            try #require(CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &allocated) == kCVReturnSuccess)
            let buffer = try #require(allocated)
            CVPixelBufferLockBaseAddress(buffer, [])
            CVPixelBufferGetBaseAddress(buffer)?.initializeMemory(as: UInt8.self, repeating: frame < 30 ? 20 : 220,
                                                                   count: CVPixelBufferGetDataSize(buffer))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            try #require(adapter.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: 2, timescale: 1))
        await writer.finishWriting()
        try #require(writer.status == .completed)
    }
}

private func makeSnapshot(at time: TimeInterval) throws -> RecordingAskFrameSnapshot {
    let size = CGSize(width: 96, height: 64)
    let context = try #require(CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(gray: 0.5, alpha: 1))
    context.fill(CGRect(origin: .zero, size: size))
    let image = try #require(context.makeImage())
    let png = try ImageExport.encode(image)
    return RecordingAskFrameSnapshot(document: CaptureDocument(original: png, width: image.width, height: image.height), time: time)
}

private actor LoadGate {
    private var requests: [TimeInterval: CheckedContinuation<RecordingAskFrameSnapshot, Error>] = [:]

    func load(_ request: RecordingAskFrameInput) async throws -> RecordingAskFrameSnapshot {
        try await withCheckedThrowingContinuation { requests[request.editedTime] = $0 }
    }

    func received(_ time: TimeInterval) async throws -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while requests[time] == nil && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        return requests[time] != nil
    }

    func finish(_ time: TimeInterval) {
        requests.removeValue(forKey: time)?.resume(with: Result { try makeSnapshot(at: time) })
    }
}

private actor TurnRecorder {
    private(set) var started: [AssistantContext] = []

    func start(_ context: AssistantContext) {
        started.append(context)
    }
}

private struct CheckingService: AssistantService {
    let provider: AssistantProvider
    let recorder: TurnRecorder
    var preview: PreviewAssistantService { PreviewAssistantService(provider: provider) }

    func availability() async -> AssistantAvailability { await preview.availability() }
    func usage() async -> AssistantUsage? { nil }
    func models() async -> [String] { [] }
    func signIn() async throws -> AssistantSignIn { throw AssistantError.signedOut(provider) }
    func signOut() async throws {}
    func startConversation(_ context: AssistantContext, model: String?) async throws -> any AssistantConversation {
        await recorder.start(context)
        return try await preview.startConversation(context, model: model)
    }
}
