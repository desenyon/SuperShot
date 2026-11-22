import Testing
import Foundation
import CoreGraphics
import ImageIO
@testable import AI

private actor MemoryLines: LineTransport {
    nonisolated let lines: AsyncStream<String>
    private let output: AsyncStream<String>.Continuation
    private(set) var writes = [WireValue]()
    private var accountType: WireValue = "chatgpt", count = 0
    private let claude: Bool
    var activeMCP = false

    init(claude: Bool = false) {
        self.claude = claude
        (lines, output) = AsyncStream.makeStream()
    }
    func setAccount(_ type: WireValue) { accountType = type }
    func enableMCP() { activeMCP = true }
    func terminate() { output.finish() }
    func diagnostics() -> String { "fixture exited" }
    func emit(_ value: WireValue) throws { output.yield(try value.line()) }
    func messages(_ method: String) -> [WireValue] { writes.filter { $0["method"].text == method } }
    func write(_ line: String) throws {
        let msg = try WireValue.parse(line)
        writes.append(msg)
        if claude {
            if msg["type"] == "control_request" {
                try emit(["type": "result", "subtype": "error_during_execution"]); return
            }
            let content = msg["message"]["content"].values
            switch content.last?["text"] {
            case "wait": try emit(["type": "stream_event", "event": ["type": "content_block_delta", "delta": ["type": "text_delta", "text": "waiting"]]])
            case "structured limit":
                try emit(["type": "rate_limit_event", "rate_limit_info": ["status": "rejected", "resetsAt": 123]])
                try emit(["type": "result", "subtype": "error_during_execution", "is_error": true, "errors": []])
            case "limit": try emit(["type": "result", "subtype": "error_during_execution", "is_error": true, "errors": ["Usage limit reached"]])
            case "fail": try emit(["type": "result", "subtype": "error_during_execution", "is_error": true, "result": "Bad input"])
            default:
                for word: WireValue in ["Hi", " 🐈"] {
                    try emit(["type": "stream_event", "event": ["type": "content_block_delta", "delta": ["type": "text_delta", "text": word]]])
                }
                try emit(["type": "result", "subtype": "success", "is_error": false, "result": "Hi 🐈"])
            }
            return
        }
        guard let method = msg["method"].text, msg["id"] != .null else { return }
        func reply(_ result: WireValue) throws { try emit(["jsonrpc": "2.0", "id": msg["id"], "result": result]) }
        let params = msg["params"]
        switch method {
        case "initialize", "account/logout", "thread/unsubscribe": try reply([:])
        case "account/read": try reply(["account": ["type": accountType, "email": "hello@example.test", "planType": "plus"]])
        case "account/login/start":
            try reply(["type": "chatgpt", "authUrl": "https://example.test/login", "loginId": "login"])
        case "account/rateLimits/read":
            try reply(["rateLimits": ["primary": ["usedPercent": 42, "resetsAt": 420], "rateLimitReachedType": "workspace_member_credits_depleted"]])
        case "model/list":
            if params["cursor"] == .null { try reply(["data": [["model": "alpha"]], "nextCursor": "more"]) }
            else { try reply(["data": [["model": "beta"]]]) }
        case "thread/start":
            count += 1; try reply(["thread": ["id": .string("thread-\(count)")]])
        case "config/read": try reply(["config": ["mcp_servers": ["browser": ["command": "x"], "trading": ["url": "https://example.test"]]]])
        case "mcpServerStatus/list":
            // Codex lists configured servers even when they are disabled for the thread.
            try reply(["data": activeMCP ? [["name": "browser", "runtimeStatus": "disabled", "tools": [:]],
                                            ["name": "trading", "runtimeStatus": "connected", "tools": ["buy": [:]]]]
                                         : [["name": "browser", "runtimeStatus": "disabled", "tools": [:]],
                                            ["name": "trading", "runtimeStatus": "disabled", "tools": [:]]]])
        case "turn/start":
            let id = params["threadId"]
            count += 1
            let turn = WireValue.string("turn-\(count)")
            try reply(["turn": ["id": turn]])
            try emit(["method": "turn/started", "params": ["threadId": id, "turn": ["id": turn]]])
            let text = params["input"].values.last?["text"]
            if text == "wait" {
                try emit(["method": "item/agentMessage/delta", "params": ["threadId": id, "turnId": turn, "itemId": "m", "delta": "waiting"]])
                return
            }
            if text == "limit" {
                try emit(["method": "turn/completed", "params": ["threadId": id, "turn": ["id": turn, "status": "failed",
                    "error": ["message": "No more requests", "codexErrorInfo": "usageLimitExceeded"]]]]); return
            }
            for word: WireValue in ["a", "b"] {
                try emit(["method": "item/agentMessage/delta", "params": ["threadId": id, "turnId": turn, "itemId": "m", "delta": word]])
            }
            try emit(["method": "item/completed", "params": ["threadId": id, "turnId": turn, "item": ["id": "m", "type": "agentMessage", "text": "ab"]]])
            try emit(["method": "turn/completed", "params": ["threadId": id, "turn": ["id": turn, "status": "completed"]]])
        case "turn/interrupt":
            try reply([:])
            try emit(["method": "turn/completed", "params": ["threadId": params["threadId"], "turn": ["id": params["turnId"], "status": "interrupted"]]])
        default: throw AssistantError.tool("Unexpected fixture request " + method)
        }
    }
}

struct AssistantTests {
    private func context(width: Int = 20, height: Int = 10) -> AssistantContext {
        let c = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return AssistantContext(image: c.makeImage()!, recognizedText: "Example", appName: "Fixture")
    }
    private func runtime(_ io: MemoryLines, version: String = "2.1.325", auth: String = "claude.ai") -> AssistantRuntime {
        AssistantRuntime(locate: { name in Harness(url: URL(fileURLWithPath: "/fixture/" + name), version: version, path: "/bin") },
                         launch: { _, _, _ in io }, command: { _, args in
            if args == ["features", "list"] {
                return LineProcess.ResultText(stdout: "plugins   stable  true\nshell_tool   stable  true\napps   stable  true\n", stderr: "", status: 0)
            }
            #expect(args == ["auth", "status", "--json"])
            return LineProcess.ResultText(stdout: #"{"loggedIn":true,"authMethod":"\#(auth)","email":"a@example.test","subscriptionType":"max"}"#, stderr: "", status: 0)
        })
    }
    private func collect(_ stream: ReplyStream) async throws -> [AssistantEvent] {
        var events = [AssistantEvent]()
        for try await event in stream { events.append(event) }
        return events
    }

    @Test func locatorOrderAndSemanticVersions() {
        let dirs = HarnessLocator.directories(path: "/first:/second:/first", home: "/home/test")
        #expect(dirs == ["/first", "/second", "/home/test/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/home/test/.npm-global/bin", "/home/test/.bun/bin"])
        #expect(HarnessLocator.find("codex", in: dirs) { ["/second/codex", "/usr/local/bin/codex"].contains($0) }?.path == "/second/codex")
        #expect(HarnessLocator.parseVersion("codex-cli 0.169.0") == "0.169.0")
        #expect(HarnessLocator.parseVersion("2.1.325 (Claude Code)") == "2.1.325")
        #expect(HarnessLocator.supports("0.170.0", minimum: "0.169.0"))
        #expect(!HarnessLocator.supports("0.99.12", minimum: "0.169.0"))
        #expect(!HarnessLocator.supports("2.1.0-rc.1", minimum: "2.1.0"))
        #expect(HarnessLocator.supports("2.1.0+build", minimum: "2.1.0"))
    }
    @Test func versionsGateBothServicesBeforeLaunch() async {
        let io = MemoryLines()
        let codex = CodexAssistantService(runtime: runtime(io, version: "0.168.9"))
        #expect(await codex.availability() == .unsupportedVersion(found: "0.168.9", minimum: "0.169.0"))
        #if DEBUG
        let claude = ClaudeCodeAssistantService(runtime: runtime(io, version: "2.0.99"))
        #expect(await claude.availability() == .unsupportedVersion(found: "2.0.99", minimum: "2.1.0"))
        #endif
        #expect(await io.writes.isEmpty)
    }

    @Test func assistantProvidersMatchTheBuildConfiguration() async throws {
        #expect(Assistant.availableProvider(named: "off") == nil)
        #if DEBUG
        #expect(Assistant.availableProviders == [.chatgpt, .claude])
        #else
        #expect(Assistant.availableProviders == [.chatgpt])
        #expect(Assistant.availableProvider(named: "claude") == nil)
        let service = Assistant.service(for: .claude)
        #expect(await service.availability() == .notInstalled)
        await #expect(throws: AssistantError.notInstalled(.claude)) { try await service.signIn() }
        await #expect(throws: AssistantError.notInstalled(.claude)) { try await service.startConversation(context(), model: nil) }
        #endif
    }
    @Test func accountHandshakeAndDenials() async throws {
        let io = MemoryLines(), tool = "/fixture/codex"
        await io.setAccount("apiKey")
        let service = CodexAssistantService(runtime: runtime(io, version: "0.169.0"))
        #expect(await service.availability() == .signedOut(toolVersion: "0.169.0", toolPath: tool))
        #expect(try await service.signIn() == .openURL(URL(string: "https://example.test/login")!))
        await #expect(throws: AssistantError.signedOut(.chatgpt)) { try await service.startConversation(context(), model: nil) }
        await io.setAccount("chatgpt")
        #expect(await service.availability() == .ready(AssistantAccount(email: "hello@example.test", plan: "Plus", toolVersion: "0.169.0", toolPath: tool)))
        let writes = await io.writes
        #expect(writes[0]["params"]["clientInfo"]["name"] == "supershot")
        #expect(writes[1] == ["method": "initialized"])
        #expect(await service.models() == ["alpha", "beta"])
        let cases: [(String, WireValue)] = [
            ("item/commandExecution/requestApproval", ["decision": "decline"]), ("item/fileChange/requestApproval", ["decision": "decline"]),
            ("execCommandApproval", ["decision": ["denied": ["rejection": "Tools are disabled in SuperShot."]]]),
            ("applyPatchApproval", ["decision": ["denied": ["rejection": "Tools are disabled in SuperShot."]]]),
            ("item/permissions/requestApproval", ["permissions": [:], "scope": "turn"]),
            ("mcpServer/elicitation/request", ["action": "decline", "content": .null]), ("item/tool/requestUserInput", ["answers": [:]])
        ]
        for (method, _) in cases { try await io.emit(["method": .string(method), "id": .string(method), "params": [:]]) }
        try await io.emit(["jsonrpc": "2.0", "id": "unknown", "method": "surprise", "params": [:]])
        // A subsequent RPC response is a barrier behind all preceding incoming lines.
        _ = await service.models()
        let responses = await io.writes
        for (method, expected) in cases { #expect(responses.contains(["id": .string(method), "result": expected])) }
        #expect(responses.first { $0["id"] == "unknown" }?["error"]["code"] == -32601)
        await io.enableMCP()
        await #expect(throws: AssistantError.self) { try await service.startConversation(context(), model: nil) }
        #expect(await io.messages("turn/start").isEmpty)
    }

    @Test func codexTurnsKeepImagesPrivateAndMapUsage() async throws {
        let io = MemoryLines(), service = CodexAssistantService(runtime: runtime(io))
        let expected = AssistantUsage(usedFraction: 0.42, resetsAt: Date(timeIntervalSince1970: 420), limitReached: true)
        #expect(await service.usage() == expected)
        let capture = context(), chat = try await service.startConversation(capture, model: "alpha")
        let attachment = AssistantAttachment(image: capture.image, label: "Region 1 · 20 × 10")
        let events = try await collect(chat.send("first", attachments: [attachment]))
        #expect(events == [.delta("a"), .delta("b"), .usage(expected), .done])
        _ = try await collect(chat.send("second", attachments: []))
        await #expect(throws: AssistantError.limitReached(resetsAt: expected.resetsAt)) { try await collect(chat.send("limit", attachments: [])) }
        let starts = await io.messages("turn/start"), thread = try #require(await io.messages("thread/start").first?["params"])
        #expect(thread["ephemeral"] == true && thread["sandbox"] == "read-only" && thread["approvalPolicy"] == "never")
        #expect(thread["config"]["mcp_servers"] == ["browser": ["enabled": false], "trading": ["enabled": false]])
        #expect(thread["baseInstructions"].text == AssistantPrompt.instructions(for: capture))
        let first = starts[0]["params"], items = first["input"].values
        #expect(items.count == 3 && items[2]["text"] == "first\n[Attached: Region 1 · 20 × 10]")
        #expect(first["model"] == "alpha" && first["sandboxPolicy"] == ["type": "readOnly", "networkAccess": false])
        #expect(starts[1]["params"]["input"].values == [["text": "second", "type": "text"]])
        for item in items.prefix(2) {
            let file = try #require(item["path"].text)
            #expect((try FileManager.default.attributesOfItem(atPath: file)[.posixPermissions] as? Int) == 0o600)
        }
        let cwd = try #require(thread["cwd"].text)
        #expect((try FileManager.default.attributesOfItem(atPath: cwd)[.posixPermissions] as? Int) == 0o700)
        await chat.close()
        #expect(!FileManager.default.fileExists(atPath: cwd))
        #expect(await io.messages("thread/unsubscribe").count == 1)
    }

    #if DEBUG
    @Test func claudePartialMessagesFollowupsAndErrors() async throws {
        let io = MemoryLines(claude: true), service = ClaudeCodeAssistantService(runtime: runtime(io))
        #expect(await service.availability() == .ready(AssistantAccount(email: "a@example.test", plan: "Max", toolVersion: "2.1.325", toolPath: "/fixture/claude")))
        #expect(try await service.signIn() == .runInTerminal(command: "claude auth login"))
        #expect(await service.models() == ["sonnet", "opus", "haiku"])
        #expect(await service.usage() == nil)
        let invalid = ClaudeCodeAssistantService(runtime: runtime(io, auth: "api_key"))
        #expect(!(await invalid.availability()).isReady)
        let capture = context(), chat = try await service.startConversation(capture, model: "opus")
        let extra = AssistantAttachment(image: capture.image, label: "Detail")
        #expect(try await collect(chat.send("one", attachments: [])) == [.delta("Hi"), .delta(" 🐈"), .done])
        _ = try await collect(chat.send("two", attachments: [extra]))
        await #expect(throws: AssistantError.limitReached(resetsAt: nil)) { try await collect(chat.send("limit", attachments: [])) }
        await #expect(throws: AssistantError.tool("Bad input")) { try await collect(chat.send("fail", attachments: [])) }
        let inputs = await io.writes.map { $0["message"]["content"].values }
        #expect(inputs.map(\.count) == [2, 2, 1, 1])
        #expect(inputs[0][0]["source"]["media_type"] == "image/png")
        #expect(inputs[1][1]["text"] == "two\n[Attached: Detail]")
        await chat.close()
    }

    #endif

    @Test func concurrentThreadsAndCancellationAreIsolated() async throws {
        let io = MemoryLines(), service = CodexAssistantService(runtime: runtime(io))
        async let first = service.startConversation(context(), model: nil)
        async let second = service.startConversation(context(), model: nil)
        let (a, b) = try await (first, second)
        var pending = a.send("wait", attachments: []).makeAsyncIterator()
        #expect(try await pending.next() == .delta("waiting"))
        await #expect(throws: AssistantError.tool("A reply is already in progress.")) { try await collect(a.send("busy", attachments: [])) }
        #expect(try await collect(b.send("separate", attachments: [])) == [.delta("a"), .delta("b"), .done])
        await a.cancel()
        do { _ = try await pending.next(); Issue.record("Expected cancellation") }
        catch { #expect(error as? AssistantError == .cancelled) }
        #expect(await io.messages("initialize").count == 1)
        let turns = await io.messages("turn/start")
        #expect(turns.count == 2 && turns[0]["params"]["threadId"] != turns[1]["params"]["threadId"])
        await io.setAccount("apiKey")
        await #expect(throws: AssistantError.signedOut(.chatgpt)) { try await collect(a.send("changed account", attachments: [])) }
        #expect(await io.messages("turn/start").count == 2)
        await a.close(); await b.close()
    }

    #if DEBUG
    @Test func claudeImmediateCancellationAndStructuredLimit() async throws {
        let io = MemoryLines(claude: true), service = ClaudeCodeAssistantService(runtime: runtime(io))
        let chat = try await service.startConversation(context(), model: nil)
        let pending = chat.send("wait", attachments: [])
        await chat.cancel()
        await #expect(throws: AssistantError.cancelled) { try await collect(pending) }
        await #expect(throws: AssistantError.limitReached(resetsAt: Date(timeIntervalSince1970: 123))) {
            try await collect(chat.send("structured limit", attachments: []))
        }
        await chat.close()
    }

    #endif

    @Test func purgeAndDownscale() throws {
        let parent = try AskDirectory()
        let root = parent.url.appendingPathComponent("private")
        let live = try AskDirectory(root: root)
        let stale = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: false)
        let now = Date().addingTimeInterval(90_000)
        AskDirectory.purgeStale(root: root, now: now)
        #expect(!FileManager.default.fileExists(atPath: stale.path))
        #expect(FileManager.default.fileExists(atPath: live.url.path))
        for (width, height, w, h) in [(2600, 130, 2000, 100), (13, 2600, 10, 2000), (2, 1, 2, 1)] {
            let data = try AskDirectory.png(context(width: width, height: height).image)
            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(image.width == w && image.height == h)
        }
        withExtendedLifetime(parent) {}
    }

    private func executable(_ name: String, in folder: AskDirectory, body: String) throws -> AssistantRuntime {
        let url = folder.url.appendingPathComponent(name)
        let bootstrap = #"""
        #!/usr/bin/python3 -I
        import base64, json, os, signal, sys, time
        signal.alarm(15)
        def emit(obj):
            raw = json.dumps(obj, ensure_ascii=False).encode() + b'\r\n'
            split = raw.find('🐈'.encode())
            if split >= 0:
                os.write(1, raw[:split+1])
                time.sleep(0.01)
                raw = raw[split+1:]
            os.write(1, raw)
        """#
        try (bootstrap + "\n" + body).write(to: url, atomically: false, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return AssistantRuntime(locate: { _ in
            let result = try? await LineProcess.run(url, ["--version"], path: "/usr/bin:/bin")
            guard let version = result.flatMap({ HarnessLocator.parseVersion($0.stdout) }) else { return nil }
            return Harness(url: url, version: version, path: "/usr/bin:/bin")
        })
    }

    @Test func codexExecutableHandlesSplitUTF8InterruptExitAndRestart() async throws {
        let folder = try AskDirectory()
        defer { folder.remove() }
        let runtime = try executable("codex", in: folder, body: #"""
        if sys.argv[1:] == ['--version']:
            print('codex-cli 0.169.0')
            sys.exit(0)
        if sys.argv[1:] == ['features', 'list']:
            print('plugins      stable  true\nshell_tool   stable  true\nhooks        stable  true')
            sys.exit(0)
        assert sys.argv[1:3] == ['app-server', '--stdio']
        disabled = [sys.argv[i + 1] for i, a in enumerate(sys.argv) if a == '--disable']
        assert 'plugins' in disabled and 'shell_tool' in disabled and 'browser_use' not in disabled, disabled
        assert os.stat('.').st_mode & 0o777 == 0o700
        initialized = False
        for line in sys.stdin:
            m = json.loads(line)
            method, params = m['method'], m.get('params')
            def reply(value): emit({'id': m['id'], 'result': value})
            def notice(method, params): emit({'method': method, 'params': dict(threadId='T', **params)})
            if method == 'initialize':
                assert params['clientInfo']['name'] == 'supershot'
                reply({})
            elif method == 'initialized': initialized = True
            elif method == 'account/read':
                assert initialized
                reply({'account': {'type': 'chatgpt', 'planType': 'pro'}})
            elif method == 'thread/start':
                assert params['config'] == {'mcp_servers': {'repl': {'enabled': False}}}, params.get('config')
                cwd = params['cwd']
                reply({'thread': {'id': 'T'}})
            elif method == 'config/read': reply({'config': {'mcp_servers': {'repl': {'command': 'node'}}}})
            elif method == 'mcpServerStatus/list':
                assert params['threadId'] == 'T'
                reply({'data': [{'name': 'repl', 'runtimeStatus': 'disabled', 'tools': {}}]})
            elif method == 'turn/start':
                inputs = params['input']
                prompt = inputs[-1]['text']
                if prompt == 'crash':
                    assert len(inputs) == 1
                    os.write(2, b'x' * 5000 + b'fixture crashed')
                    sys.exit(3)
                image = inputs[0]['path']
                assert os.path.dirname(image) == cwd
                assert open(image, 'rb').read(8) == b'\x89PNG\r\n\x1a\n'
                reply({'turn': {'id': 'A'}})
                notice('item/agentMessage/delta', {'turnId':'A', 'itemId':'M', 'delta':'ready 🐈'})
            elif method == 'turn/interrupt':
                assert params == {'threadId':'T', 'turnId':'A'}
                reply({})
                notice('turn/completed', {'turn':{'id':'A','status':'interrupted'}})
            elif method == 'thread/unsubscribe': reply({})
            else: raise AssertionError(method)
        """#)
        let service = CodexAssistantService(runtime: runtime), chat = try await service.startConversation(context(), model: nil)
        var events = chat.send("wait", attachments: []).makeAsyncIterator()
        #expect(try await events.next() == .delta("ready 🐈"))
        await chat.cancel()
        do { _ = try await events.next(); Issue.record("Expected cancellation") }
        catch { #expect(error as? AssistantError == .cancelled) }
        do { _ = try await collect(chat.send("crash", attachments: [])); Issue.record("Expected process failure") }
        catch let AssistantError.tool(message) {
            #expect(message.utf8.count == 4096)
            #expect(message.hasSuffix("fixture crashed"))
        }
        #expect((await service.availability()).isReady)
        await chat.close()
    }

    #if DEBUG
    @Test func claudeExecutableKeepsOneProcessAndScalesImages() async throws {
        let folder = try AskDirectory()
        defer { folder.remove() }
        let runtime = try executable("claude", in: folder, body: #"""
        args = sys.argv[1:]
        if args == ['--version']:
            print('2.1.325 (Claude Code)')
            sys.exit(0)
        if args == ['auth', 'status', '--json']:
            emit({'loggedIn':True, 'authMethod':'claude.ai', 'subscriptionType':'max'})
            sys.exit(0)
        def option(key): return args[args.index(key)+1]
        assert option('--tools') == option('--setting-sources') == ''
        assert option('--input-format') == option('--output-format') == 'stream-json'
        assert all(x in args for x in ['-p','--include-partial-messages','--strict-mcp-config','--no-session-persistence','--verbose'])
        assert option('--model') == 'sonnet' and 'SuperShot' in option('--system-prompt')
        assert os.stat('.').st_mode & 0o777 == 0o700
        for n, line in enumerate(sys.stdin):
            m = json.loads(line)
            assert m['type'] == 'user'
            content = m['message']['content']
            assert len(content) == (2 if n == 0 else 1)
            if n == 0:
                png = base64.b64decode(content[0]['source']['data'])
                assert png[:8] == b'\x89PNG\r\n\x1a\n' and int.from_bytes(png[16:20],'big') == 2000
            else: assert len(content[0]['text']) == 80000
            emit({'type':'stream_event','event':{'type':'content_block_delta','delta':{'type':'text_delta','text':'ok 🐈'}}})
            emit({'type':'result','is_error':False,'subtype':'success','result':'ok 🐈'})
        """#)
        let service = ClaudeCodeAssistantService(runtime: runtime)
        let chat = try await service.startConversation(context(width: 3000, height: 100), model: "sonnet")
        for prompt in ["one", String(repeating: "a", count: 80_000)] {
            #expect(try await collect(chat.send(prompt, attachments: [])) == [.delta("ok 🐈"), .done])
        }
        await chat.close()
        await #expect(throws: AssistantError.cancelled) { try await collect(chat.send("closed", attachments: [])) }
    }
    #endif
}

extension AssistantTests {
    @Test func featureListAndMCPInventoryParsing() {
        let names = CodexAssistantService.featureNames("apps                stable  true\nbrowser_use   stable  true\n\n")
        #expect(names == ["apps", "browser_use"])
        #expect(CodexAssistantService.featureNames(nil) == nil && CodexAssistantService.featureNames("") == nil)
        #expect(CodexAssistantService.mcpServerNames(["b": [:], "a": [:]]) == ["a", "b"])
        #expect(CodexAssistantService.mcpServerNames(.null).isEmpty)
        let disabled: WireValue = [["name": "a", "runtimeStatus": "disabled", "tools": [:]]]
        #expect(CodexAssistantService.liveMCPServer(disabled) == nil)
        #expect(CodexAssistantService.liveMCPServer([["name": "b", "runtimeStatus": "failed"]]) == "b")
        #expect(CodexAssistantService.liveMCPServer([["name": "c", "runtimeStatus": "disabled", "tools": ["t": [:]]]]) == "c")
    }
}
