import Foundation
import Darwin
import Synchronization

protocol LineTransport: Sendable {
    var lines: AsyncStream<String> { get }
    func write(_ line: String) async throws
    func terminate() async
    func diagnostics() async -> String
}

actor LineProcess: LineTransport {
    nonisolated let lines: AsyncStream<String>
    private let process: Process
    private let input: FileHandle
    private let output: PipeOutput
    private let directory: AskDirectory
    private let writer = DispatchQueue(label: "SuperShot.Ask.stdin", qos: .utility)

    init(_ executable: URL, _ arguments: [String], directory: AskDirectory, path: String) throws {
        self.directory = directory
        let process = Process(), stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory.url
        var environment = ProcessInfo.processInfo.environment
        // The CLI owns subscription authentication. Prevent inherited API/provider overrides.
        for key in environment.keys where key.hasPrefix("ANTHROPIC_") || key.hasPrefix("OPENAI_") ||
            key.hasPrefix("CLAUDE_CODE_USE_") || ["CLAUDE_CODE_OAUTH_TOKEN", "CODEX_API_KEY", "CLAUDE_CODE_OAUTH_TOKEN_FILE_DESCRIPTOR", "CLAUDE_CODE_API_KEY_FILE_DESCRIPTOR"].contains(key) {
            environment.removeValue(forKey: key)
        }
        environment["PATH"] = path
        process.environment = environment
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        input = stdin.fileHandleForWriting
        _ = fcntl(input.fileDescriptor, F_SETNOSIGPIPE, 1)
        let (lines, continuation) = AsyncStream<String>.makeStream()
        self.lines = lines
        let output = PipeOutput(stdout.fileHandleForReading, stderr.fileHandleForReading, continuation)
        self.output = output
        self.process = process
        process.terminationHandler = { [writer, input] child in
            output.finish(status: child.terminationStatus)
            writer.async { try? input.close() }
        }
        do { try process.run() }
        catch { output.finish(status: -1); throw error }
    }

    func write(_ line: String) async throws {
        guard !line.utf8.contains(10), process.isRunning else { throw AssistantError.tool(output.message) }
        let data = Data((line + "\n").utf8), handle = input
        try await withCheckedThrowingContinuation { (result: CheckedContinuation<Void, Error>) in
            writer.async { result.resume(with: Result { try handle.write(contentsOf: data) }) }
        }
    }
    func terminate() { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
    deinit { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
    func diagnostics() -> String { output.message }
    func status() -> Int32? { output.status }

    struct ResultText: Sendable { let stdout: String, stderr: String, status: Int32 }
    static func run(_ executable: URL, _ arguments: [String], path: String, timeout: Duration = .seconds(10)) async throws -> ResultText {
        let child = try LineProcess(executable, arguments, directory: AskDirectory(), path: path)
        let timer = Task {
            try await Task.sleep(for: timeout)
            await child.terminate()
        }
        defer { timer.cancel() }
        return await withTaskCancellationHandler {
            var lines = [String]()
            for await line in child.lines { lines.append(line) }
            return await ResultText(stdout: lines.joined(separator: "\n"), stderr: child.diagnostics(), status: child.status() ?? -1)
        } onCancel: { Task { await child.terminate() } }
    }
}

// The serial queue owns both descriptors and the incomplete stdout line. On exit drain
// both pipes before finishing the stream, even when a descendant inherited a pipe.
private final class PipeOutput: @unchecked Sendable {
    private let queue = DispatchQueue(label: "SuperShot.Ask.output", qos: .utility)
    private let stdout: FileHandle, stderr: FileHandle
    private let continuation: AsyncStream<String>.Continuation
    private var sources = [any DispatchSourceRead]()
    private var partial = Data(), finished = false
    private let result = Mutex((tail: Data(), status: Optional<Int32>.none))
    var status: Int32? { result.withLock { $0.status } }
    var message: String {
        result.withLock {
            let text = String(decoding: $0.tail, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? "The assistant process exited." : text
        }
    }

    init(_ stdout: FileHandle, _ stderr: FileHandle, _ continuation: AsyncStream<String>.Continuation) {
        self.stdout = stdout; self.stderr = stderr; self.continuation = continuation
        for handle in [stdout, stderr] {
            let fd = handle.fileDescriptor
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            sources.append(source)
            source.setEventHandler { [weak self] in self?.drain(handle) }
            source.setCancelHandler { try? handle.close() }
        }
        for source in sources { source.activate() }
    }
    func finish(status: Int32) {
        queue.async {
            self.drain(self.stdout); self.drain(self.stderr)
            self.finished = true
            for source in self.sources { source.cancel() }
            if !self.partial.isEmpty { self.emitLine() }
            self.result.withLock { $0.status = status }
            self.continuation.finish()
        }
    }
    private func drain(_ handle: FileHandle) {
        let source = sources[handle === stdout ? 0 : 1]
        guard !finished, !source.isCancelled else { return }
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = Darwin.read(handle.fileDescriptor, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            if count <= 0 {
                if count == 0 { source.cancel() }
                return
            }
            let bytes = buffer.prefix(count)
            if handle === stderr {
                result.withLock { $0.tail.append(contentsOf: bytes); $0.tail = $0.tail.suffix(4096) }
            } else {
                var start = bytes.startIndex
                for newline in bytes.indices where bytes[newline] == 10 {
                    partial.append(contentsOf: bytes[start..<newline]); emitLine()
                    start = newline + 1
                }
                partial.append(contentsOf: bytes[start...])
            }
        }
    }
    private func emitLine() {
        if partial.last == 13 { partial.removeLast() }
        continuation.yield(String(decoding: partial, as: UTF8.self))
        partial.removeAll(keepingCapacity: true)
    }
}
