import Foundation

actor CodexAssistantService: AssistantService {
    nonisolated let provider = AssistantProvider.chatgpt
    private let runtime: AssistantRuntime
    private var connection: CodexConnection?
    private var starting: Task<CodexConnection, Error>?
    init(runtime: AssistantRuntime = AssistantRuntime()) { self.runtime = runtime }

    private func server() async throws -> CodexConnection {
        if let connection {
            if await connection.isOpen { return connection }
            if self.connection !== connection { return try await server() }
            self.connection = nil
        }
        if let starting { return try await starting.value }
        let task = Task { [runtime] in
            let tool = try await runtime.harness(.chatgpt)
            // Codex rejects unknown feature names, so only disable the ones this version has.
            let known = Self.featureNames(try? await runtime.command(tool, ["features", "list"]).stdout)
            let arguments = ["app-server", "--stdio", "-c", "web_search=\"disabled\"", "-c", "model_provider=\"openai\""]
                + Self.disabledFeatures.filter { known?.contains($0) ?? true }.flatMap { ["--disable", $0] }
            let transport = try await runtime.launch(tool, arguments, AskDirectory())
            let client = CodexConnection(tool: tool, transport: transport)
            do { try await client.initialize(); return client }
            catch { await transport.terminate(); throw error }
        }
        starting = task
        defer { starting = nil }
        let result = try await task.value
        connection = result
        return result
    }
    /// Tool surfaces Ask never needs. MCP servers are disabled per thread in `CodexConnection.start`,
    /// because a `-c` override merges with the user's config instead of replacing it.
    static let disabledFeatures = ["plugins", "apps", "hooks", "shell_tool", "unified_exec", "code_mode", "multi_agent",
                                   "multi_agent_v2", "view_image", "standalone_web_search", "browser_use",
                                   "browser_use_external", "in_app_browser", "browser_annotation_api"]
    /// Feature names from `codex features list` (first column), or nil when the list is unavailable.
    static func featureNames(_ output: String?) -> Set<String>? {
        guard let output else { return nil }
        let names = output.split(separator: "\n").compactMap { $0.split(separator: " ", omittingEmptySubsequences: true).first.map(String.init) }
        return names.isEmpty ? nil : Set(names)
    }
    static func mcpServerNames(_ configured: WireValue) -> [String] {
        if case .object(let servers) = configured { return servers.keys.sorted() }
        return []
    }
    /// The first server that is not disabled or that exposes tools, if any.
    static func liveMCPServer(_ data: WireValue) -> String? {
        data.values.first { entry in
            let tools: Int = if case .object(let t) = entry["tools"] { t.count } else { 0 }
            return entry["runtimeStatus"].text != "disabled" || tools > 0
        }.map { $0["name"].text ?? "unknown" }
    }
    func availability() async -> AssistantAvailability {
        do {
            let client = try await server()
            return try await client.account().map(AssistantAvailability.ready) ?? client.tool.signedOut
        } catch {
            if let tool = try? await runtime.harness(provider) { return tool.signedOut }
            return AssistantRuntime.unavailable(error)
        }
    }
    func signIn() async throws -> AssistantSignIn {
        let response = try await server().request("account/login/start", ["type": "chatgpt"])
        guard response["type"] == "chatgpt", let raw = response["authUrl"].text,
              let url = URL(string: raw), url.scheme == "https", url.host != nil else {
            throw AssistantError.tool("Codex did not return a sign-in URL.")
        }
        return .openURL(url)
    }
    func signOut() async throws { _ = try await server().request("account/logout") }
    func usage() async -> AssistantUsage? { try? await server().readUsage() }
    func models() async -> [String] {
        do {
            let client = try await server()
            var models = [String](), seen = Set<String>(), cursor: WireValue = .null
            repeat {
                let page = try await client.request("model/list", ["cursor": cursor])
                models += page["data"].values.compactMap { $0["model"].text ?? $0["id"].text }
                cursor = page["nextCursor"]
            } while cursor.text.map({ seen.insert($0).inserted }) == true
            return models
        } catch { return [] }
    }
    func startConversation(_ context: AssistantContext, model: String?) async throws -> any AssistantConversation {
        let client = try await server()
        guard try await client.account() != nil else { throw AssistantError.signedOut(provider) }
        return try await client.start(context, model: model)
    }
}

private actor CodexConnection {
    let tool: Harness
    private let transport: any LineTransport
    private var exitError: AssistantError?
    var isOpen: Bool { exitError == nil }
    private var nextID = 0
    private struct Request {
        let result: CheckedContinuation<WireValue, Error>, timeout: Task<Void, Never>
    }
    private var pending = [Int: Request]()
    private var usage: AssistantUsage?
    private struct Turn {
        let token: UUID, stream: ReplyStream.Continuation
        var id: String?, cancelled = false, streamedItems = Set<String>()
        var error: AssistantError?
    }
    private struct ThreadState {
        var screenshot: AssistantContext?
        let model: String?, directory: AskDirectory
        var turn: Turn?
    }
    private var threads = [String: ThreadState]()

    init(tool: Harness, transport: any LineTransport) { self.tool = tool; self.transport = transport }
    deinit { let transport = transport; Task { await transport.terminate() } }

    func initialize() async throws {
        Task { [weak self, transport] in
            do {
                for await line in transport.lines where !line.isEmpty {
                    try await self?.receive(WireValue.parse(line))
                }
                await self?.end(.tool(await transport.diagnostics()))
            } catch {
                await self?.end(.tool("Invalid Codex protocol message: " + error.localizedDescription))
                await transport.terminate()
            }
        }
        _ = try await request("initialize", ["clientInfo": ["name": "supershot", "title": "SuperShot", "version": "1"],
                                              "capabilities": ["experimentalApi": true, "explicitGatewayOauth": true]])
        try await write(["method": "initialized"])
    }
    private func write(_ value: WireValue) async throws { try await transport.write(value.line()) }

    func request(_ method: String, _ params: WireValue = .null) async throws -> WireValue {
        if let exitError { throw exitError }
        nextID += 1
        let id = nextID
        let message: WireValue = ["id": .integer(Int64(id)), "method": .string(method), "params": params]
        return try await withCheckedThrowingContinuation { result in
            let timeout = Task {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                // A timed-out mutating request has an unknown outcome. Retire its connection.
                end(.tool("Codex timed out on " + method + "."))
                await transport.terminate()
            }
            pending[id] = Request(result: result, timeout: timeout)
            Task {
                do { try await write(message) }
                catch {
                    end(.tool(await transport.diagnostics()))
                    await transport.terminate()
                }
            }
        }
    }
    private func end(_ error: AssistantError) {
        guard exitError == nil else { return }
        exitError = error
        for call in pending.values { call.timeout.cancel(); call.result.resume(throwing: error) }
        pending.removeAll()
        for state in threads.values { state.turn?.stream.finish(throwing: error); state.directory.remove() }
        threads.removeAll()
    }
    func account() async throws -> AssistantAccount? {
        let account = try await request("account/read", ["refreshToken": false])["account"]
        guard account["type"] == "chatgpt" else { usage = nil; return nil }
        return AssistantAccount(email: account["email"].text, plan: account["planType"].text?.replacingOccurrences(of: "_", with: " ").capitalized,
                                toolVersion: tool.version, toolPath: tool.url.path)
    }
    func readUsage() async throws -> AssistantUsage? {
        usage = Self.parseUsage(try await request("account/rateLimits/read"))
        return usage
    }
    static func parseUsage(_ data: WireValue) -> AssistantUsage? {
        let snapshot = data["rateLimits"], window = snapshot["primary"]
        guard case .object = snapshot else { return nil }
        return AssistantUsage(usedFraction: window["usedPercent"].number.map { min(1, max(0, $0 / 100)) },
                              resetsAt: window["resetsAt"].number.map(Date.init(timeIntervalSince1970:)),
                              limitReached: snapshot["rateLimitReachedType"].text != nil || snapshot["spendControlReached"] == true || data["ordinaryUsageAllowed"] == false)
    }
    func start(_ context: AssistantContext, model: String?) async throws -> any AssistantConversation {
        let directory = try AskDirectory()
        // Turn off every MCP server the user configured, for this thread only. The user's config is never written.
        let configured = try await request("config/read", ["cwd": .string(directory.url.path), "includeLayers": false])["config"]["mcp_servers"]
        let servers = CodexAssistantService.mcpServerNames(configured)
        let response = try await request("thread/start", [
            "cwd": .string(directory.url.path), "baseInstructions": .string(AssistantPrompt.instructions(for: context)),
            "developerInstructions": "Answer using the supplied images and text only. Never invoke tools.",
            "model": model.map(WireValue.string) ?? .null, "modelProvider": "openai", "ephemeral": true,
            "approvalPolicy": "never", "sandbox": "read-only", "environments": [], "dynamicTools": [],
            "config": ["mcp_servers": .object(Dictionary(uniqueKeysWithValues: servers.map { ($0, ["enabled": false]) }))]
        ])
        guard let id = response["thread"]["id"].text else { throw AssistantError.tool("Codex did not return a thread ID.") }
        do {
            // Fail closed before the first turn if any MCP server is still live or exposes tools.
            var cursor: WireValue = .null
            repeat {
                let page = try await request("mcpServerStatus/list", ["threadId": .string(id), "limit": 50, "cursor": cursor, "detail": "toolsAndAuthOnly"])
                if let live = CodexAssistantService.liveMCPServer(page["data"]) {
                    throw AssistantError.tool("Codex could not turn off the MCP server “\(live)” for this conversation, so SuperShot did not send the image.")
                }
                cursor = page["nextCursor"]
            } while cursor != .null
        } catch {
            _ = try? await request("thread/unsubscribe", ["threadId": .string(id)])
            throw error
        }
        threads[id] = ThreadState(screenshot: context, model: model, directory: directory)
        return CodexConversation(client: self, id: id)
    }

    func send(thread id: String, ticket: ReplySubmission.Ticket, text: String, attachments: [AssistantAttachment], stream: ReplyStream.Continuation) async {
        let token = ticket.id
        guard let state = threads[id], !ticket.isCancelled else { stream.finish(throwing: exitError ?? .cancelled); return }
        guard state.turn == nil else { stream.finish(throwing: AssistantError.tool("A reply is already in progress.")); return }
        threads[id]?.turn = Turn(token: token, stream: stream)
        do {
            guard try await account() != nil else { throw AssistantError.signedOut(.chatgpt) }
            guard !ticket.isCancelled, threads[id]?.turn?.token == token, threads[id]?.turn?.cancelled == false else { throw AssistantError.cancelled }
            let images = (state.screenshot.map { [$0.image] } ?? []) + attachments.map(\.image)
            var input = try images.map { image -> WireValue in
                ["type": "localImage", "path": .string(try state.directory.writePNG(image).path)]
            }
            input.append(["type": "text", "text": .string(question(text, with: attachments))])
            let response = try await request("turn/start", ["threadId": .string(id), "input": .array(input),
                "model": state.model.map(WireValue.string) ?? .null, "approvalPolicy": "never",
                "sandboxPolicy": ["type": "readOnly", "networkAccess": false]])
            guard let turnID = response["turn"]["id"].text else { throw AssistantError.tool("Codex did not return a turn ID.") }
            threads[id]?.screenshot = nil
            if threads[id]?.turn?.token == token {
                identify(thread: id, turn: turnID)
            } else if threads[id] == nil {
                _ = try? await interrupt(id, turnID)
            }
        } catch {
            if threads[id]?.turn?.token == token { finish(id, error: error) }
        }
    }

    private func interrupt(_ thread: String, _ turn: String) async throws {
        _ = try await request("turn/interrupt", ["threadId": .string(thread), "turnId": .string(turn)])
    }
    private func identify(thread: String, turn: String) {
        guard let active = threads[thread]?.turn, active.id == nil else { return }
        threads[thread]?.turn?.id = turn
        if active.cancelled { Task { try? await interrupt(thread, turn) } }
    }
    func cancel(_ id: String, token: UUID? = nil) async {
        guard let turn = threads[id]?.turn, token == nil || token == turn.token, !turn.cancelled else { return }
        threads[id]?.turn?.cancelled = true
        if let turnID = turn.id {
            do { try await interrupt(id, turnID) }
            catch { if threads[id]?.turn?.token == turn.token { finish(id, error: error) } }
        }
    }
    func close(_ id: String) async {
        guard let state = threads.removeValue(forKey: id) else { return }
        state.turn?.stream.finish(throwing: AssistantError.cancelled)
        state.directory.remove()
        if let turn = state.turn?.id { try? await interrupt(id, turn) }
        _ = try? await request("thread/unsubscribe", ["threadId": .string(id)])
    }
    private func finish(_ id: String, error: Error? = nil) {
        guard let turn = threads[id]?.turn else { return }
        threads[id]?.turn = nil
        if let error { turn.stream.finish(throwing: error) }
        else if turn.cancelled { turn.stream.finish(throwing: AssistantError.cancelled) }
        else {
            if let usage { turn.stream.yield(.usage(usage)) }
            turn.stream.yield(.done); turn.stream.finish()
        }
    }

    private func receive(_ message: WireValue) async throws {
        let id = message["id"]
        if let method = message["method"].text {
            if id != .null { try await write(Self.denial(method, id: id, version: message["jsonrpc"])); return }
            notification(method, message["params"])
        } else if let number = id.number, let key = Int(exactly: number), let call = pending.removeValue(forKey: key) {
            call.timeout.cancel()
            if message["error"] != .null {
                let error = message["error"]
                call.result.resume(throwing: replyError(error["message"].text ?? "Codex request failed.",
                                                       code: error["data"]["codexErrorInfo"].text, reset: usage?.resetsAt))
            } else { call.result.resume(returning: message["result"]) }
        }
    }
    private static func denial(_ method: String, id: WireValue, version: WireValue) -> WireValue {
        var response = ["id": id]
        if version == "2.0" { response["jsonrpc"] = version }
        let result: WireValue
        switch method {
        case "item/commandExecution/requestApproval", "item/fileChange/requestApproval": result = ["decision": "decline"]
        case "execCommandApproval", "applyPatchApproval": result = ["decision": ["denied": ["rejection": "Tools are disabled in SuperShot."]]]
        case "item/permissions/requestApproval": result = ["permissions": [:], "scope": "turn"]
        case "item/tool/requestUserInput": result = ["answers": [:]]
        case "mcpServer/elicitation/request": result = ["action": "decline", "content": .null]
        case "item/tool/call": result = ["success": false, "contentItems": []]
        default:
            response["error"] = ["code": -32601, "message": "Unsupported server request."]
            return .object(response)
        }
        response["result"] = result
        return .object(response)
    }
    private func notification(_ method: String, _ data: WireValue) {
        switch method {
        case "account/rateLimits/updated": usage = Self.parseUsage(data); return
        case "account/updated", "account/login/completed": usage = nil; return
        default: break
        }
        guard let id = data["threadId"].text, let active = threads[id]?.turn,
              let turnID = data["turnId"].text ?? data["turn"]["id"].text,
              active.id == nil || active.id == turnID else { return }
        identify(thread: id, turn: turnID)
        switch method {
        case "item/agentMessage/delta":
            if let delta = data["delta"].text, !delta.isEmpty, !active.cancelled {
                if let item = data["itemId"].text { threads[id]?.turn?.streamedItems.insert(item) }
                active.stream.yield(.delta(delta))
            }
        case "item/completed":
            let item = data["item"]
            if item["type"] == "agentMessage", let key = item["id"].text, !active.streamedItems.contains(key),
               let text = item["text"].text, !text.isEmpty, !active.cancelled { active.stream.yield(.delta(text)) }
        case "error":
            if data["willRetry"] != true { threads[id]?.turn?.error = turnError(data["error"]) }
        case "turn/completed":
            threads[id]?.screenshot = nil
            let turn = data["turn"]
            switch turn["status"].text {
            case "completed": finish(id, error: active.error)
            case "interrupted": finish(id, error: AssistantError.cancelled)
            default: finish(id, error: active.error ?? turnError(turn["error"]))
            }
        default: break
        }
    }
    private func turnError(_ error: WireValue) -> AssistantError {
        replyError(error["message"].text ?? "Codex could not finish the reply.", code: error["codexErrorInfo"].text, reset: usage?.resetsAt)
    }
}

private final class CodexConversation: AssistantConversation {
    private let submission = ReplySubmission()
    let client: CodexConnection, id: String
    init(client: CodexConnection, id: String) { self.client = client; self.id = id }
    func send(_ text: String, attachments: [AssistantAttachment]) -> ReplyStream {
        submission.stream { [client, id] ticket, stream in
            await client.send(thread: id, ticket: ticket, text: text, attachments: attachments, stream: stream)
        } interrupt: { await self.client.cancel(self.id, token: $0) }
    }
    func cancel() async { await submission.cancel { await client.cancel(id, token: $0) } }
    func close() async { await client.close(id) }
    deinit { let client = client, id = id; Task { await client.close(id) } }
}
