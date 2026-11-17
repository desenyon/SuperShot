import AppKit
let app=NSApplication.shared
app.setActivationPolicy(.regular)
let window=NSWindow(contentRect:NSRect(x:160,y:160,width:900,height:600),styleMask:[.titled,.closable],backing:.buffered,defer:false)
window.title="SuperShot Capture Fixture"
final class Fixture: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill(); bounds.fill()
        for row in 0..<6 { for column in 0..<9 {
            (row % 2 == column % 2 ? NSColor(calibratedWhite:0.9,alpha:1) : .white).setFill()
            NSRect(x:column*100,y:row*100,width:100,height:100).fill()
        }}
        NSColor.systemRed.setFill(); NSRect(x:0,y:0,width:100,height:100).fill()
        NSColor.systemBlue.setFill(); NSRect(x:800,y:0,width:100,height:100).fill()
        NSColor.systemGreen.setFill(); NSRect(x:0,y:500,width:100,height:100).fill()
        let attrs:[NSAttributedString.Key:Any]=[.font:NSFont.monospacedSystemFont(ofSize:24,weight:.medium),.foregroundColor:NSColor.black]
        ("SuperShot · Capture verification\n900 × 600 points\nTop left: red / Bottom left: green\nOriginal pixels. Local only." as NSString).draw(in:NSRect(x:140,y:180,width:650,height:220),withAttributes:attrs)
    }
}
window.contentView=Fixture(frame:NSRect(x:0,y:0,width:900,height:600))
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps:true)
app.run()
