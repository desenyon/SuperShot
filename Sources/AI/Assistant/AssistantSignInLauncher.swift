import AppKit

/// Continues a sign-in that a tool started: opens its browser page, or runs its login command in Terminal.
/// Used by both the Ask panel and Settings so sign-in behaves the same everywhere.
public enum AssistantSignInLauncher {
    @MainActor public static func launch(_ signIn: AssistantSignIn) throws {
        switch signIn {
        case .openURL(let url):
            NSWorkspace.shared.open(url)
        case .runInTerminal(let command):
            // A .command file opens in Terminal and runs, with no Automation permission prompt.
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SuperShot-SignIn", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let script = folder.appendingPathComponent("Sign in.command")
            let body = "#!/bin/zsh -l\nclear\necho 'SuperShot: signing in. Follow the steps below, then return to SuperShot.'\necho\n\(command)\necho\necho 'You can close this window.'\n"
            try body.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
                throw AssistantError.tool("Terminal is not available. Run \(command) in a terminal, then return to SuperShot.")
            }
            NSWorkspace.shared.open([script], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
