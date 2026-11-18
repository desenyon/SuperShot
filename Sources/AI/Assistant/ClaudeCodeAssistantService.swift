import Foundation

actor ClaudeCodeAssistantService: AssistantService {
    nonisolated let provider = AssistantProvider.claude
    let runtime: AssistantRuntime
    init(runtime: AssistantRuntime = AssistantRuntime()) { self.runtime = runtime }

    private func account(_ tool: Harness) async throws -> AssistantAccount? {
        let result = try await runtime.command(tool, ["auth", "status", "--json"])
        let status = try WireValue.parse(result.stdout)
        guard result.status == 0, status["loggedIn"] == true, status["authMethod"] == "claude.ai",
              status["apiProvider"] == .null || status["apiProvider"] == "firstParty" else { return nil }
        return AssistantAccount(email: status["email"].text,
                                plan: (status["subscriptionType"].text ?? status["planTier"].text)?.capitalized,
                                toolVersion: tool.version, toolPath: tool.url.path)
    }
    func availability() async -> AssistantAvailability {
        do {
            let tool = try await runtime.harness(provider)
            return (try? await account(tool)).map(AssistantAvailability.ready) ?? tool.signedOut
        } catch { return AssistantRuntime.unavailable(error) }
    }
    func signIn() async throws -> AssistantSignIn {
        _ = try await runtime.harness(provider)
        return .runInTerminal(command: "claude auth login")
    }
    func signOut() async throws {
        let result = try await runtime.command(runtime.harness(provider), ["auth", "logout"])
        if result.status != 0 { throw AssistantError.tool(result.stderr) }
    }
    func usage() async -> AssistantUsage? { nil }
    func models() async -> [String] { ["sonnet", "opus", "haiku"] }
    func startConversation(_ context: AssistantContext, model: String?) async throws -> any AssistantConversation {
        let tool = try await runtime.harness(provider)
        guard try await account(tool) != nil else { throw AssistantError.signedOut(provider) }
        let directory = try AskDirectory()
        var arguments = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                         "--include-partial-messages", "--tools", "", "--setting-sources", "", "--strict-mcp-config",
                         "--no-session-persistence", "--system-prompt", AssistantPrompt.instructions(for: context)]
        if HarnessLocator.supports(tool.version, minimum: "2.1.325") { arguments += ["--safe-mode", "--no-chrome", "--disable-slash-commands"] }
        if let model { arguments += ["--model", model] }
        let transport = try await runtime.launch(tool, arguments, directory)
        let conversation = ClaudeConversation(context: context, directory: directory, transport: transport)
        await conversation.listen()
        return conversation
    }
}

private actor ClaudeConversation: AssistantConversation {
    let directory: AskDirectory, transport: any LineTransport
    private var screenshot: AssistantContext?
    private var closed: AssistantError?
    private struct Turn {
        let token: UUID, stream: ReplyStream.Continuation
        var streamed = false, cancelled = false, limited = false
        var resetsAt: Date?
    }
    private let submission = ReplySubmission()
    private var turn: Turn?, interruptTimeout: Task<Void, Never>?

    init(context: AssistantContext, directory: AskDirectory, transport: any LineTransport) {
        screenshot = context; self.directory = directory; self.transport = transport
    }
    func listen() {
        Task { [weak self, transport] in
            do {
                for await line in transport.lines where !line.isEmpty { try await self?.receive(WireValue.parse(line)) }
                await self?.end(.tool(await transport.diagnostics()))
            } catch {
                await self?.end(.tool("Invalid Claude Code protocol message: " + error.localizedDescription))
                await transport.terminate()
            }
        }
    }
    nonisolated func send(_ text: String, attachments: [AssistantAttachment]) -> ReplyStream {
        submission.stream { ticket, stream in
            await self.begin(text, attachments, ticket: ticket, stream: stream)
        } interrupt: { await self.interrupt(token: $0) }
    }
    private func begin(_ text: String, _ attachments: [AssistantAttachment], ticket: ReplySubmission.Ticket, stream: ReplyStream.Continuation) async {
        if let closed { stream.finish(throwing: closed); return }
        guard !ticket.isCancelled else { stream.finish(throwing: AssistantError.cancelled); return }
        guard turn == nil else { stream.finish(throwing: AssistantError.tool("A reply is already in progress.")); return }
        turn = Turn(token: ticket.id, stream: stream)
        do {
            let images = (screenshot.map { [$0.image] } ?? []) + attachments.map(\.image)
            var content = try images.map { image -> WireValue in
                ["type": "image", "source": ["type": "base64", "media_type": "image/png",
                                             "data": .string(try AskDirectory.png(image).base64EncodedString())]]
            }
            content.append(["type": "text", "text": .string(question(text, with: attachments))])
            let message: WireValue = ["type": "user", "message": ["role": "user", "content": .array(content)]]
            try await transport.write(message.line())
            screenshot = nil
        } catch {
            end(.tool(error.localizedDescription))
            await transport.terminate()
        }
    }
    private func receive(_ data: WireValue) {
        guard let active = turn else { return }
        switch data["type"] {
        case "stream_event":
            let event = data["event"], delta = event["delta"]
            if event["type"] == "content_block_delta", delta["type"] == "text_delta", let text = delta["text"].text, !active.cancelled {
                turn?.streamed = true; active.stream.yield(.delta(text))
            }
        case "rate_limit_event":
            let info = data["rate_limit_info"]
            if info["status"] == "rejected" {
                turn?.limited = true; turn?.resetsAt = info["resetsAt"].number.map(Date.init(timeIntervalSince1970:))
            }
        case "assistant":
            if data["error"] == "rate_limit" { turn?.limited = true }
        case "result":
            turn = nil
            screenshot = nil
            interruptTimeout?.cancel(); interruptTimeout = nil
            if active.cancelled { active.stream.finish(throwing: AssistantError.cancelled) }
            else if active.limited { active.stream.finish(throwing: AssistantError.limitReached(resetsAt: active.resetsAt)) }
            else if data["is_error"] == true || data["subtype"] != "success" {
                let details = ([data["result"].text] + data["errors"].values.map(\.text)).compactMap { $0 }.joined(separator: "\n")
                active.stream.finish(throwing: replyError(details.isEmpty ? "Claude Code could not finish the reply." : details,
                                                          code: data["subtype"].text))
            } else {
                if !active.streamed, let text = data["result"].text, !text.isEmpty { active.stream.yield(.delta(text)) }
                active.stream.yield(.done); active.stream.finish()
            }
        default: break
        }
    }
    func cancel() async { await submission.cancel { await self.interrupt(token: $0) } }
    private func interrupt(token: UUID?) async {
        guard let active = turn, !active.cancelled, token == nil || token == active.token else { return }
        turn?.cancelled = true
        let message: WireValue = ["type": "control_request", "request_id": .string(UUID().uuidString), "request": ["subtype": "interrupt"]]
        interruptTimeout = Task {
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            if turn?.token == active.token { await close() }
        }
        do { try await transport.write(message.line()) }
        catch { await close() }
    }
    private func end(_ error: AssistantError) {
        guard closed == nil else { return }
        closed = error
        interruptTimeout?.cancel(); interruptTimeout = nil
        turn?.stream.finish(throwing: error); turn = nil
        screenshot = nil; directory.remove()
    }
    func close() async { end(.cancelled); await transport.terminate() }
    deinit { let transport = transport; Task { await transport.terminate() } }
}
