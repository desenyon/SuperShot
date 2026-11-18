import AI
import CoreGraphics
import Foundation
import Observation
import Document
import Recognition

public typealias AssistantFactory = @Sendable (AssistantProvider) -> any AssistantService

public struct AskOptions: Equatable, Sendable {
    public var provider: AssistantProvider
    public var model: String?
    public var confirmBeforeSending: Bool
    public var includeRecognizedText: Bool
    public var redactBeforeSending: Bool
    public var suggestions: [String]
    public init(provider: AssistantProvider = .chatgpt, model: String? = nil, confirmBeforeSending: Bool = true,
                includeRecognizedText: Bool = true, redactBeforeSending: Bool = false, suggestions: [String] = []) {
        self.provider = provider
        self.model = model
        self.confirmBeforeSending = confirmBeforeSending
        self.includeRecognizedText = includeRecognizedText
        self.redactBeforeSending = redactBeforeSending
        self.suggestions = suggestions
    }
}

public struct AskMessage: Identifiable, Equatable, Sendable {
    public enum Role: Sendable { case user, assistant }
    public enum Status: Sendable { case streaming, done, failed }
    public let id = UUID()
    public let role: Role
    public var text: String
    public var attachments: [String]
    public var status: Status
    public init(_ role: Role, _ text: String, attachments: [String] = [], status: Status = .done) {
        self.role = role; self.text = text; self.attachments = attachments; self.status = status
    }
}

@MainActor @Observable public final class AskModel {
    public private(set) var options: AskOptions
    public private(set) var availability: AssistantAvailability?
    public private(set) var usage: AssistantUsage?
    public private(set) var messages: [AskMessage]
    public var draft = ""
    public private(set) var regions: [AskRegion] = []
    public private(set) var awaitingConsent = false
    public private(set) var waitingForBrowser = false
    public private(set) var sensitiveCount: Int?
    @ObservationIgnored private var inspection: Task<AskCapture, Error>?
    public private(set) var error: String?
    public private(set) var isSending = false
    public private(set) var nextRegion = 1
    public var isStreaming: Bool { isSending || messages.last?.status == .streaming }
    public var canSend: Bool {
        availability?.isReady == true && usage?.limitReached != true && !isStreaming && !awaitingConsent &&
            !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    public var transcript: String {
        messages.filter { !$0.text.isEmpty }.map { "\($0.role == .user ? "You" : "Assistant"): \($0.text)" }.joined(separator: "\n\n")
    }
    public var otherProvider: AssistantProvider { options.provider == .chatgpt ? .claude : .chatgpt }

    private let factory: AssistantFactory
    private var service: any AssistantService
    private var conversation: (any AssistantConversation)?
    private var contextCapture: AskCapture?
    private var consented = false
    private var hidesDetails = false
    private var summary = ""
    private struct Question {
        let message: AskMessage
        let document: CaptureDocument
        let regions: [AskRegion]
    }
    private var pending: Question?
    private var resubmittedMessageID: UUID?
    @ObservationIgnored private var deltaBuffer = ""
    @ObservationIgnored private var deltaFlush: Task<Void, Never>?
    var captureImage: CGImage? { contextCapture?.image }
    var captureDocument: CaptureDocument? { contextCapture?.document }
    var includesEarlierMessages: Bool { !summary.isEmpty }
    private var turn: Task<Void, Never>?
    private var login: Task<Void, Never>?
    private var generation = UUID()

    public init(options: AskOptions, factory: @escaping AssistantFactory, messages: [AskMessage] = []) {
        self.options = options; self.factory = factory; self.messages = messages
        service = factory(options.provider)
    }

    isolated deinit {
        login?.cancel(); inspection?.cancel()
        turn?.cancel()
        if let conversation { Task { await conversation.close() } }
    }

    public func refreshAvailability() async {
        let id = generation, service = service
        let state = await service.availability()
        let currentUsage = state.isReady ? await service.usage() : nil
        guard id == generation, !Task.isCancelled else { return }
        availability = state; usage = currentUsage
    }

    public func attach(_ rect: CGRect, in document: CaptureDocument) {
        let rect = rect.integral.intersection(document.visibleBounds)
        guard !rect.isEmpty else { return }
        regions.append(AskRegion(document: document, rect: rect, number: nextRegion))
        nextRegion += 1
    }
    public func removeRegion(_ id: UUID) { regions.removeAll { $0.id == id } }

    public func send(document: CaptureDocument) {
        guard canSend else { return }
        let question = AskMessage(.user, draft.trimmingCharacters(in: .whitespacesAndNewlines), attachments: regions.map(\.label))
        // The old provider's unanswered turn remains visible until its replacement is submitted.
        if let id = resubmittedMessageID {
            messages.removeAll { $0.id == id }
            if messages.last?.status == .failed && messages.last?.text.isEmpty == true { messages.removeLast() }
            resubmittedMessageID = nil
        }
        pending = Question(message: question, document: document, regions: regions)
        messages.append(question); draft = ""; regions = []; error = nil
        if options.confirmBeforeSending && !consented {
            awaitingConsent = true
            inspectLocally(document, questionID: question.id)
        }
        else { confirm(redact: hidesDetails || options.redactBeforeSending) }
    }

    private func inspectLocally(_ document: CaptureDocument, questionID: UUID) {
        sensitiveCount = nil
        inspection?.cancel()
        let task = Task { try await AskCapture.prepare(document, recognize: true) }
        inspection = task
        Task { [weak self] in
            let count = try? await task.value.candidates.count
            guard self?.pending?.message.id == questionID else { return }
            self?.sensitiveCount = count
        }
    }

    public func confirm(redact: Bool) {
        guard let pending, !isSending, availability?.isReady == true else { return }
        consented = true; awaitingConsent = false; hidesDetails = redact || options.redactBeforeSending
        let reply = AskMessage(.assistant, "", status: .streaming)
        messages.append(reply); isSending = true; error = nil
        turn = Task { [weak self] in
            guard let self else { return }
            do {
                let session = try await session(for: pending.document)
                try Task.checkCancellation()
                let attachments = try await attachments(for: pending)
                try Task.checkCancellation()
                let history = summary
                let excerpts = hidesDetails && !history.isEmpty ? await Task.detached { AskCapture.coverSensitiveLines(history) }.value : history
                try Task.checkCancellation()
                let prompt = excerpts.isEmpty ? pending.message.text : "Earlier conversation (excerpts):\n\(excerpts)\n\nNew question: \(pending.message.text)"
                for try await event in session.send(prompt, attachments: attachments) {
                    try Task.checkCancellation()
                    switch event {
                    case .delta(let text): collectDelta(text)
                    case .usage(let value): usage = value
                    case .done: break
                    }
                    if event == .done { break }
                }
                try Task.checkCancellation()
                summary = ""; self.pending = nil; finishReply(.done)
            } catch {
                guard !Task.isCancelled else { return }
                finishReply(.failed)
                retireSession(); rememberTranscript()
                handle(error)
            }
        }
    }

    private func session(for document: CaptureDocument) async throws -> any AssistantConversation {
        if let conversation { return conversation }
        let capture: AskCapture
        if let inspection, options.includeRecognizedText || hidesDetails { capture = try await inspection.value }
        else { capture = try await AskCapture.prepare(document, recognize: options.includeRecognizedText || hidesDetails) }
        try Task.checkCancellation()
        inspection?.cancel(); inspection = nil
        let redact = hidesDetails, includeText = options.includeRecognizedText
        let context = try await Task.detached { try capture.context(redact: redact, includeText: includeText) }.value
        try Task.checkCancellation()
        let session = try await service.startConversation(context, model: options.model)
        if Task.isCancelled { await session.close(); throw CancellationError() }
        contextCapture = capture; conversation = session
        return session
    }

    private func attachments(for question: Question) async throws -> [AssistantAttachment] {
        var result: [AssistantAttachment] = []
        var last = contextCapture
        let redact = hidesDetails
        for region in question.regions {
            if last?.document != region.document {
                last = try await AskCapture.prepare(region.document, recognize: redact)
            }
            try Task.checkCancellation()
            guard let capture = last else { throw AssistantError.tool("The selected region is unavailable.") }
            let rect = AskCapture.pixelRect(region.rect, in: region.document)
            guard let image = try await Task.detached(operation: { try capture.pixels(redact: redact).cropping(to: rect) }).value else {
                throw AssistantError.tool("The selected region could not be read.")
            }
            result.append(AssistantAttachment(image: image, label: region.label))
        }
        return result
    }

    func matchingRegion(in reply: String, document: CaptureDocument, editorText: [TextRegion] = []) -> CGRect? {
        let capture = contextCapture?.document == document ? contextCapture : nil
        let folded = reply.lowercased()
        let quotes = reply.matches(of: /["“`*]([^"”`*\n]+)["”`*]/).map { String($0.1).lowercased() }
        let matches: (TextRegion) -> Bool = { region in
            let text = region.text.lowercased()
            return text.count > 1 && (folded.contains(text) || quotes.contains { $0.count > 1 && text.contains($0) })
        }
        guard let line = capture?.recognition.text.first(where: matches) else {
            return editorText.first(where: { document.visibleBounds.intersects($0.rect) && matches($0) })?.rect
        }
        let origin = AskCapture.pixelRect(document.visibleBounds, in: document).origin
        return line.rect.offsetBy(dx: document.visibleBounds.minX - origin.x, dy: document.visibleBounds.minY - origin.y)
    }

    // Several transport chunks may arrive in one display frame. Coalesce them into a single
    // observable string change, including the last partial chunk when the user presses Stop.
    private func collectDelta(_ text: String) {
        deltaBuffer += text
        guard deltaFlush == nil else { return }
        deltaFlush = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(32)); self?.flushDeltas() } catch {}
        }
    }
    private func flushDeltas() {
        deltaFlush?.cancel(); deltaFlush = nil
        if !deltaBuffer.isEmpty, messages.last?.role == .assistant {
            messages[messages.count - 1].text += deltaBuffer
        }
        deltaBuffer = ""
    }
    private func finishReply(_ status: AskMessage.Status) {
        flushDeltas()
        if messages.last?.role == .assistant { messages[messages.count - 1].status = status }
        isSending = false; turn = nil
    }

    public func stop() {
        guard isSending else { return }
        turn?.cancel()
        finishReply(.done)
        pending = nil
        retireSession(cancel: true)
        rememberTranscript()
    }

    private func retireSession(cancel: Bool = false) {
        inspection?.cancel(); inspection = nil; sensitiveCount = nil
        let old = conversation
        conversation = nil; contextCapture = nil
        Task { if cancel { await old?.cancel() }; await old?.close() }
    }
    private func rememberTranscript() {
        summary = messages.filter { !$0.text.isEmpty && $0.id != pending?.message.id }.suffix(12).map {
            "\($0.role == .user ? "User" : "Assistant"): \($0.text.prefix(400))"
        }.joined(separator: "\n")
    }

    private func handle(_ failure: Error) {
        switch failure as? AssistantError {
        case .notInstalled: availability = .notInstalled
        case .unsupportedVersion(_, let found, let minimum): availability = .unsupportedVersion(found: found, minimum: minimum)
        case .signedOut: availability = .signedOut(toolVersion: "", toolPath: "")
        case .limitReached(let date): usage = AssistantUsage(usedFraction: 1, resetsAt: date, limitReached: true)
        case .cancelled: error = "The reply stopped before it finished."
        default: error = failure.localizedDescription
        }
    }

    public func retry() {
        guard !isSending else { return }
        if messages.last?.status == .failed { messages.removeLast() }
        error = nil
        if pending != nil {
            retireSession(); rememberTranscript()
            if options.confirmBeforeSending && !consented { awaitingConsent = true }
            else { confirm(redact: hidesDetails) }
        } else { Task { await refreshAvailability() } }
    }

    public func cancelConsent() {
        guard awaitingConsent, let pending else { return }
        inspection?.cancel(); inspection = nil; sensitiveCount = nil
        draft = pending.message.text; regions = pending.regions
        messages.removeAll { $0.id == pending.message.id }
        self.pending = nil; awaitingConsent = false
    }

    public func newConversation() {
        stop(); retireSession(); cancelConsent()
        messages = []; regions = []; draft = ""; pending = nil; summary = ""; nextRegion = 1
        consented = false; hidesDetails = false; error = nil; resubmittedMessageID = nil
    }

    public func switchProvider(_ provider: AssistantProvider) {
        guard provider != options.provider else { return }
        cancelConsent()
        if let pending, !isSending {
            draft = pending.message.text; regions = pending.regions
            resubmittedMessageID = pending.message.id
        }
        stop(); retireSession(); rememberTranscript()
        generation = UUID(); login?.cancel(); waitingForBrowser = false; pending = nil
        service = factory(provider); options.provider = provider; options.model = nil
        consented = false; availability = nil; usage = nil; error = nil
        Task { await refreshAvailability() }
    }

    public func end() {
        generation = UUID(); login?.cancel(); waitingForBrowser = false
        stop(); retireSession()
    }

    public func updateOptions(_ updated: AskOptions, changedProvider: Bool) {
        if changedProvider { switchProvider(updated.provider) }
        var next = updated
        if !changedProvider && next.provider != options.provider {
            next.provider = options.provider; next.model = options.model
        }
        if next.model != options.model || next.redactBeforeSending != options.redactBeforeSending ||
            next.includeRecognizedText != options.includeRecognizedText {
            stop(); retireSession(); rememberTranscript(); consented = false; hidesDetails = next.redactBeforeSending
        }
        options = next
    }

    public func signIn() {
        guard !waitingForBrowser else { return }
        waitingForBrowser = true; error = nil
        login = Task { [weak self, service] in
            do {
                let next = try await service.signIn()
                try Task.checkCancellation()
                try AssistantSignInLauncher.launch(next)
                let deadline = ContinuousClock.now + .seconds(300)
                while ContinuousClock.now < deadline {
                    try await Task.sleep(for: .seconds(2))
                    let state = await service.availability()
                    try Task.checkCancellation()
                    guard let self else { return }
                    availability = state
                    if state.isReady {
                        waitingForBrowser = false
                        await refreshAvailability()
                        if pending != nil { retry() }
                        return
                    }
                }
                self?.error = "Sign-in timed out. Try again when you’re ready."
            } catch {
                guard !Task.isCancelled else { return }
                self?.handle(error)
            }
            self?.waitingForBrowser = false
        }
    }
}
