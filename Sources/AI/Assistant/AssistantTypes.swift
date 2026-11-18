import Foundation
import CoreGraphics

/// Chat about a capture, answered by a subscription CLI the user already signed in to.
/// SuperShot never holds a password, token, or API key: Codex and Claude Code own sign-in
/// and run as local child processes. Nothing is sent until the user asks a question.
public enum AssistantProvider: String, Codable, CaseIterable, Sendable, Identifiable {
    /// ChatGPT through `codex app-server`. The default.
    case chatgpt
    /// Claude through headless Claude Code (`claude -p`). The second choice.
    case claude
    public var id: String { rawValue }
    public var title: String { switch self { case .chatgpt: "ChatGPT"; case .claude: "Claude" } }
    /// The local tool that carries the conversation.
    public var toolName: String { switch self { case .chatgpt: "Codex"; case .claude: "Claude Code" } }
    /// Who receives the image. Shown before the first upload.
    public var vendor: String { switch self { case .chatgpt: "OpenAI"; case .claude: "Anthropic" } }
}

public struct AssistantAccount: Equatable, Sendable {
    public var email: String?
    /// Plan name as the tool reports it, for example "Plus" or "Max".
    public var plan: String?
    public var toolVersion: String
    public var toolPath: String
    public init(email: String? = nil, plan: String? = nil, toolVersion: String, toolPath: String) {
        self.email = email; self.plan = plan; self.toolVersion = toolVersion; self.toolPath = toolPath
    }
}

public enum AssistantAvailability: Equatable, Sendable {
    case notInstalled
    /// Installed, but a version SuperShot has not been tested with.
    case unsupportedVersion(found: String, minimum: String)
    case signedOut(toolVersion: String, toolPath: String)
    case ready(AssistantAccount)
    public var isReady: Bool { if case .ready = self { true } else { false } }
}

public struct AssistantUsage: Equatable, Sendable {
    /// 0...1 of the plan's current window, when the tool reports it.
    public var usedFraction: Double?
    public var resetsAt: Date?
    public var limitReached: Bool
    public init(usedFraction: Double? = nil, resetsAt: Date? = nil, limitReached: Bool = false) {
        self.usedFraction = usedFraction; self.resetsAt = resetsAt; self.limitReached = limitReached
    }
}

/// How sign-in continues after SuperShot asks for it.
public enum AssistantSignIn: Equatable, Sendable {
    /// Open this URL in the browser; `AssistantService.availability()` turns `.ready` when done.
    case openURL(URL)
    /// The tool only signs in from a terminal. SuperShot opens Terminal with this command.
    case runInTerminal(command: String)
}

/// Everything a conversation knows about the capture. Built once per conversation.
public struct AssistantContext: @unchecked Sendable {
    public var image: CGImage
    public var recognizedText: String?
    public var appName: String?
    public var windowTitle: String?
    public init(image: CGImage, recognizedText: String? = nil, appName: String? = nil, windowTitle: String? = nil) {
        self.image = image; self.recognizedText = recognizedText; self.appName = appName; self.windowTitle = windowTitle
    }
}

/// An extra image sent with one question, such as a region the user dragged on the canvas.
public struct AssistantAttachment: @unchecked Sendable {
    public var image: CGImage
    /// Short label the model sees and the UI shows, for example "Region 1 · 212 × 52".
    public var label: String
    public init(image: CGImage, label: String) { self.image = image; self.label = label }
}

public enum AssistantEvent: Equatable, Sendable {
    /// Streamed reply text, appended in order.
    case delta(String)
    case usage(AssistantUsage)
    case done
}

public enum AssistantError: LocalizedError, Equatable {
    case notInstalled(AssistantProvider)
    case unsupportedVersion(AssistantProvider, found: String, minimum: String)
    case signedOut(AssistantProvider)
    case limitReached(resetsAt: Date?)
    case cancelled
    /// The tool exited or sent something SuperShot could not read.
    case tool(String)
    public var errorDescription: String? {
        switch self {
        case .notInstalled(let p): "\(p.toolName) is not installed on this Mac."
        case .unsupportedVersion(let p, let found, let minimum): "\(p.toolName) \(found) is older than \(minimum). Update it, then try again."
        case .signedOut(let p): "Sign in to \(p.title) to ask about captures."
        case .limitReached: "Your plan's usage limit has been reached."
        case .cancelled: "Stopped."
        case .tool(let message): message
        }
    }
}

public protocol AssistantService: Sendable {
    var provider: AssistantProvider { get }
    func availability() async -> AssistantAvailability
    func signIn() async throws -> AssistantSignIn
    func signOut() async throws
    func usage() async -> AssistantUsage?
    /// Model identifiers the tool offers; empty when it does not list them.
    func models() async -> [String]
    func startConversation(_ context: AssistantContext, model: String?) async throws -> any AssistantConversation
}

public protocol AssistantConversation: Sendable {
    /// Streams one reply. Follow-up questions keep the earlier turns as context.
    func send(_ text: String, attachments: [AssistantAttachment]) -> AsyncThrowingStream<AssistantEvent, Error>
    /// Stops the reply in progress, if any.
    func cancel() async
    /// Ends the conversation and releases its process and temporary files.
    func close() async
}

/// Instructions given to either tool for every conversation.
public enum AssistantPrompt {
    public static func instructions(for context: AssistantContext) -> String {
        var lines = [
            "You are the assistant inside SuperShot, a macOS screenshot app.",
            "The user attached a screenshot and is asking about it. Answer from what is visible in the image.",
            "Be concise and concrete. Use short paragraphs or numbered steps. Say so when something is not visible or cannot be known from the image.",
            "You cannot run commands, browse, or edit files. Never ask to."
        ]
        var source: [String] = []
        if let app = context.appName, !app.isEmpty { source.append("App: \(app)") }
        if let title = context.windowTitle, !title.isEmpty { source.append("Window: \(title)") }
        source.append("Size: \(context.image.width) × \(context.image.height) px")
        lines.append("Capture details. " + source.joined(separator: ". ") + ".")
        if let text = context.recognizedText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            lines.append("Text recognized on this Mac (may contain errors):\n" + String(text.prefix(6000)))
        }
        return lines.joined(separator: "\n\n")
    }
}

/// Scripted service for offscreen previews and UI tests. Never starts a process.
public struct PreviewAssistantService: AssistantService {
    public let provider: AssistantProvider
    public var state: AssistantAvailability
    public var reply: String
    public var currentUsage: AssistantUsage?
    public init(provider: AssistantProvider = .chatgpt,
                state: AssistantAvailability = .ready(AssistantAccount(email: "you@example.com", plan: "Plus", toolVersion: "0.169.0", toolPath: "/usr/local/bin/codex")),
                reply: String = "This is a preview reply.", usage: AssistantUsage? = AssistantUsage(usedFraction: 0.18)) {
        self.provider = provider; self.state = state; self.reply = reply; self.currentUsage = usage
    }
    public func availability() async -> AssistantAvailability { state }
    public func signIn() async throws -> AssistantSignIn { .openURL(URL(string: "https://example.com/sign-in")!) }
    public func signOut() async throws {}
    public func usage() async -> AssistantUsage? { currentUsage }
    public func models() async -> [String] { [] }
    public func startConversation(_ context: AssistantContext, model: String?) async throws -> any AssistantConversation {
        guard state.isReady else { throw AssistantError.signedOut(provider) }
        return PreviewConversation(reply: reply)
    }
    struct PreviewConversation: AssistantConversation {
        let reply: String
        func send(_ text: String, attachments: [AssistantAttachment]) -> AsyncThrowingStream<AssistantEvent, Error> {
            let words = reply.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
            return AsyncThrowingStream { continuation in
                for (index, word) in words.enumerated() { continuation.yield(.delta(index == 0 ? word : " " + word)) }
                continuation.yield(.done); continuation.finish()
            }
        }
        func cancel() async {}
        func close() async {}
    }
}
