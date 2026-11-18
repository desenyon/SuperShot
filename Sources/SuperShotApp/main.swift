import AppKit
import DesignSystem

let app = NSApplication.shared
if let index = CommandLine.arguments.firstIndex(of: "--render-previews"), CommandLine.arguments.count > index + 2 {
    // Offscreen UI snapshots for review. Shows no windows and never activates the app.
    app.setActivationPolicy(.prohibited)
    PreviewRenderer.run(output: URL(fileURLWithPath: CommandLine.arguments[index + 1]),
                        fixture: URL(fileURLWithPath: CommandLine.arguments[index + 2]))
    exit(0)
}
if let index = CommandLine.arguments.firstIndex(of: "--render-app-icon"), CommandLine.arguments.count > index + 1 {
    // Draws the app icon from the same Brand code the app uses, for scripts/bundle.sh.
    app.setActivationPolicy(.prohibited)
    do { try Brand.writeIconPNG(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])); exit(0) }
    catch { FileHandle.standardError.write(Data("\(error)\n".utf8)); exit(1) }
}
let delegate = AppDelegate()
app.delegate = delegate
app.run()
