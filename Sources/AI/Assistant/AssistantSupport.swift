import Foundation
import CoreGraphics
import Darwin
import Synchronization
import Export

public enum Assistant {
    private static let codex = CodexAssistantService()
    #if DEBUG
    private static let claude = ClaudeCodeAssistantService()
    public static let availableProviders: [AssistantProvider] = [.chatgpt, .claude]
    #else
    public static let availableProviders: [AssistantProvider] = [.chatgpt]
    #endif
    private static let cleanup = Task.detached(priority: .utility) { AskDirectory.purgeStale() }

    public static func availableProvider(named name: String) -> AssistantProvider? {
        availableProviders.first { $0.rawValue == name }
    }

    public static func service(for provider: AssistantProvider) -> any AssistantService {
        _ = cleanup
        switch provider {
        case .chatgpt: return codex
        case .claude:
            #if DEBUG
            return claude
            #else
            return UnavailableClaudeService()
            #endif
        }
    }
    public static func purgeStale() { AskDirectory.purgeStale() }
}

#if !DEBUG
private struct UnavailableClaudeService: AssistantService {
    let provider = AssistantProvider.claude
    func availability() async -> AssistantAvailability { .notInstalled }
    func signIn() async throws -> AssistantSignIn { throw AssistantError.notInstalled(provider) }
    func signOut() async throws { throw AssistantError.notInstalled(provider) }
    func usage() async -> AssistantUsage? { nil }
    func models() async -> [String] { [] }
    func startConversation(_ context: AssistantContext, model: String?) async throws -> any AssistantConversation {
        throw AssistantError.notInstalled(provider)
    }
}
#endif

final class AskDirectory: Sendable {
    static let root = FileManager.default.temporaryDirectory.appendingPathComponent("SuperShot-Ask", isDirectory: true)
    let url: URL
    private let descriptor: Mutex<Int32?>

    init(root: URL = AskDirectory.root) throws {
        if mkdir(root.path, 0o700) != 0 && errno != EEXIST { throw POSIXError(.EACCES) }
        guard Self.isPrivate(root) else { throw POSIXError(.EACCES) }
        url = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        guard mkdir(url.path, 0o700) == 0 else { throw POSIXError(.EACCES) }
        let fd = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0, flock(fd, LOCK_SH) == 0 else {
            if fd >= 0 { Darwin.close(fd) }
            try? FileManager.default.removeItem(at: url)
            throw POSIXError(.EACCES)
        }
        descriptor = Mutex(fd)
    }
    func writePNG(_ image: CGImage) throws -> URL {
        let data = try Self.png(image)
        let file = url.appendingPathComponent(UUID().uuidString + ".png")
        let fd = open(file.path, O_CREAT | O_WRONLY | O_EXCL | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw POSIXError(.EACCES) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do { try handle.write(contentsOf: data); try handle.close(); return file }
        catch { try? FileManager.default.removeItem(at: file); throw error }
    }
    static func png(_ image: CGImage) throws -> Data {
        let longest = max(image.width, image.height)
        let scaled = longest > 2000 ? try ImageExport.transformed(image, factor: 2000 / Double(longest)) : image
        return try ImageExport.encode(scaled)
    }
    func remove() {
        descriptor.withLock { fd in
            guard let openFD = fd else { return }
            try? FileManager.default.removeItem(at: url)
            Darwin.close(openFD); fd = nil
        }
    }
    deinit { remove() }

    private static func isPrivate(_ root: URL) -> Bool {
        var info = stat()
        return lstat(root.path, &info) == 0 && info.st_uid == getuid() &&
            info.st_mode & S_IFMT == S_IFDIR && info.st_mode & 0o077 == 0
    }

    static func purgeStale(root: URL = root, now: Date = Date()) {
        guard isPrivate(root) else { return }
        let files = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for file in files where UUID(uuidString: file.lastPathComponent) != nil {
            let fd = open(file.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { continue }
            defer { Darwin.close(fd) }
            var info = stat()
            guard flock(fd, LOCK_EX | LOCK_NB) == 0, fstat(fd, &info) == 0,
                  Double(info.st_mtimespec.tv_sec) < now.timeIntervalSince1970 - 86_400 else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }
}

// Keep heterogeneous wire values Sendable across the process and conversation actors.
enum WireValue: Codable, Equatable, Sendable, ExpressibleByDictionaryLiteral, ExpressibleByArrayLiteral,
                ExpressibleByStringLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral {
    case object([String: Self]), array([Self]), string(String), integer(Int64), number(Double), bool(Bool), null
    init(dictionaryLiteral elements: (String, Self)...) { self = .object(Dictionary(uniqueKeysWithValues: elements)) }
    init(arrayLiteral elements: Self...) { self = .array(elements) }
    init(stringLiteral value: String) { self = .string(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(integerLiteral value: Int) { self = .integer(Int64(value)) }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let i = try? c.decode(Int64.self) { self = .integer(i) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([Self].self) { self = .array(a) }
        else { self = .object(try c.decode([String: Self].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .integer(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    subscript(_ key: String) -> Self {
        if case .object(let o) = self { return o[key] ?? .null }; return .null
    }
    var text: String? { if case .string(let s) = self { return s }; return nil }
    var number: Double? { switch self { case .number(let n): n; case .integer(let i): Double(i); default: nil } }
    var values: [Self] { if case .array(let a) = self { return a }; return [] }
    static func parse(_ line: String) throws -> Self { try JSONDecoder().decode(Self.self, from: Data(line.utf8)) }
    func line() throws -> String { String(decoding: try JSONEncoder().encode(self), as: UTF8.self) }
}

typealias ReplyStream = AsyncThrowingStream<AssistantEvent, Error>

// Reserve the turn synchronously so cancel() immediately after send() also stops a
// submission that has not reached its conversation actor yet.
final class ReplySubmission: Sendable {
    final class Ticket: Sendable {
        let id = UUID()
        private let stopped = Mutex(false)
        var isCancelled: Bool { stopped.withLock { $0 } }
        func cancel() { stopped.withLock { $0 = true } }
    }
    private let current = Mutex<Ticket?>(nil)
    func stream(begin: @escaping @Sendable (Ticket, ReplyStream.Continuation) async -> Void,
                interrupt: @escaping @Sendable (UUID) async -> Void) -> ReplyStream {
        let ticket = Ticket()
        return ReplyStream { stream in
            let reserved = current.withLock { current in
                guard current == nil else { return false }
                current = ticket; return true
            }
            guard reserved else { stream.finish(throwing: AssistantError.tool("A reply is already in progress.")); return }
            stream.onTermination = { [self] reason in
                current.withLock { if $0 === ticket { $0 = nil } }
                if case .cancelled = reason { ticket.cancel(); Task { await interrupt(ticket.id) } }
            }
            Task { await begin(ticket, stream) }
        }
    }
    func cancel(_ interrupt: @Sendable (UUID) async -> Void) async {
        guard let ticket = current.withLock({ $0 }) else { return }
        ticket.cancel(); await interrupt(ticket.id)
    }
}

func question(_ text: String, with attachments: [AssistantAttachment]) -> String {
    ([text] + attachments.map { "[Attached: \($0.label)]" }).joined(separator: "\n")
}

func replyError(_ message: String, code: String? = nil, reset: Date? = nil) -> AssistantError {
    let detail = ((code ?? "") + " " + message).lowercased()
    if ["ratelimit", "usagelimit", "rate limit", "rate-limit", "usage limit", "429", "rate_limit", "usage_limit", "hit your limit", "hit your session limit", "hit your weekly limit"].contains(where: detail.contains) {
        return .limitReached(resetsAt: reset)
    }
    return .tool(message)
}
