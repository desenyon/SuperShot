import AppKit

let app = NSApplication.shared
if let index = CommandLine.arguments.firstIndex(of: "--render-previews"), CommandLine.arguments.count > index + 2 {
    // Offscreen UI snapshots for review. Shows no windows and never activates the app.
    app.setActivationPolicy(.prohibited)
    PreviewRenderer.run(output: URL(fileURLWithPath: CommandLine.arguments[index + 1]),
                        fixture: URL(fileURLWithPath: CommandLine.arguments[index + 2]))
    exit(0)
}
let delegate = AppDelegate()
app.delegate = delegate
app.run()
