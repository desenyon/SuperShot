import AppKit

// A deterministic, local-only document for manual scrolling-capture checks.
final class ScrollFixture: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.97, alpha: 1).setFill(); dirtyRect.fill()
        let title: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 36, weight: .semibold), .foregroundColor: NSColor.black]
        let body: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 19, weight: .regular), .foregroundColor: NSColor.darkGray]
        ("FIELD NOTES / SCROLL STUDY" as NSString).draw(at: NSPoint(x: 48, y: 32), withAttributes: title)
        for row in 0..<36 {
            let y = 120 + row * 126
            let rect = NSRect(x: 48, y: y, width: 704, height: 100)
            guard rect.intersects(dirtyRect) else { continue }
            NSColor(calibratedHue: CGFloat((row * 37) % 100) / 100, saturation: 0.18, brightness: 0.92, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14).fill()
            (String(format: "%02d / A small observation worth keeping", row + 1) as NSString).draw(at: NSPoint(x: 72, y: y + 18), withAttributes: body)
            ("Reference \(row * 7919 + 101) · Local pixels · No network" as NSString).draw(at: NSPoint(x: 72, y: y + 54), withAttributes: body)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let window = NSWindow(contentRect: NSRect(x: 120, y: 160, width: 800, height: 640), styleMask: [.titled, .closable], backing: .buffered, defer: false)
window.title = "SuperShot Scrolling Fixture"
let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 640))
scroll.hasVerticalScroller = true
scroll.documentView = ScrollFixture(frame: NSRect(x: 0, y: 0, width: 800, height: 4700))
window.contentView = scroll
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
app.run()
