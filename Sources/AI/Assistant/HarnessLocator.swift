import Foundation

struct Harness: Sendable, Equatable {
    let url: URL, version: String, path: String
    var signedOut: AssistantAvailability { .signedOut(toolVersion: version, toolPath: url.path) }
}

struct HarnessLocator: Sendable {
    static let processPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
    private static let loginPath = Task.detached(priority: .utility) {
        let result = try? await LineProcess.run(URL(fileURLWithPath: "/bin/zsh"), ["-lc", #"printf %s "$PATH""#],
                                                path: processPath, timeout: .seconds(3))
        guard let result, result.status == 0, let path = result.stdout.split(separator: "\n").last,
              !path.isEmpty else { return processPath }
        return String(path)
    }

    static func directories(path: String, home: String = NSHomeDirectory()) -> [String] {
        var seen = Set<String>()
        return (path.components(separatedBy: ":") + [home + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin",
                                                      home + "/.npm-global/bin", home + "/.bun/bin"])
            .filter { $0.hasPrefix("/") && seen.insert($0).inserted }
    }
    static func find(_ name: String, in directories: [String], exists: (String) -> Bool) -> URL? {
        directories.lazy.map { URL(fileURLWithPath: $0).appendingPathComponent(name) }.first { exists($0.path) }
    }
    static func locate(_ name: String) async -> Harness? {
        let dirs = directories(path: await loginPath.value)
        let url = find(name, in: dirs) { path in
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && !directory.boolValue &&
                FileManager.default.isExecutableFile(atPath: path)
        }
        guard let url else { return nil }
        let path = dirs.joined(separator: ":")
        let result = try? await LineProcess.run(url, ["--version"], path: path)
        let version = result.flatMap { $0.status == 0 ? parseVersion($0.stdout) : nil } ?? "unknown"
        return Harness(url: url, version: version, path: path)
    }
    static func parseVersion(_ output: String) -> String? {
        output.split(whereSeparator: \.isWhitespace).map(String.init).first {
            $0.range(of: #"^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.+-]+)?$"#, options: .regularExpression) != nil
        }
    }
    static func supports(_ version: String, minimum: String) -> Bool {
        let release = version.split(separator: "+", maxSplits: 1).first ?? ""
        let parts = release.split(separator: "-", maxSplits: 1)
        let components = parts.first?.components(separatedBy: ".") ?? []
        guard !components.isEmpty, components.allSatisfy({ Int($0) != nil }) else { return false }
        let lhs = components.compactMap(Int.init), rhs = minimum.components(separatedBy: ".").compactMap(Int.init)
        for i in 0..<max(lhs.count, rhs.count) {
            let a = i < lhs.count ? lhs[i] : 0, b = i < rhs.count ? rhs[i] : 0
            if a != b { return a > b }
        }
        return parts.count == 1
    }
}

struct AssistantRuntime: Sendable {
    var locate: @Sendable (String) async -> Harness? = HarnessLocator.locate
    var launch: @Sendable (Harness, [String], AskDirectory) async throws -> any LineTransport = {
        try LineProcess($0.url, $1, directory: $2, path: $0.path)
    }
    var command: @Sendable (Harness, [String]) async throws -> LineProcess.ResultText = {
        try await LineProcess.run($0.url, $1, path: $0.path)
    }

    func harness(_ provider: AssistantProvider) async throws -> Harness {
        let minimum = provider == .chatgpt ? "0.169.0" : "2.1.0"
        guard let tool = await locate(provider == .chatgpt ? "codex" : "claude") else { throw AssistantError.notInstalled(provider) }
        guard HarnessLocator.supports(tool.version, minimum: minimum) else {
            throw AssistantError.unsupportedVersion(provider, found: tool.version, minimum: minimum)
        }
        return tool
    }
    static func unavailable(_ error: Error) -> AssistantAvailability {
        if case AssistantError.unsupportedVersion(_, let found, let minimum) = error {
            return .unsupportedVersion(found: found, minimum: minimum)
        }
        return .notInstalled
    }
}
