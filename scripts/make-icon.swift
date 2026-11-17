import AppKit
let output = CommandLine.arguments[1]
let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let bounds = NSRect(x: 64, y: 64, width: 896, height: 896)
NSColor(calibratedRed: 0.055, green: 0.065, blue: 0.08, alpha: 1).setFill()
NSBezierPath(roundedRect: bounds, xRadius: 200, yRadius: 200).fill()
NSColor(calibratedRed: 0.663, green: 0.78, blue: 1, alpha: 1).setStroke()
for (x, y, sx, sy) in [(300.0,300.0,1.0,1.0),(724,300,-1,1),(300,724,1,-1),(724,724,-1,-1)] {
    let p = NSBezierPath()
    p.lineWidth = 44; p.lineCapStyle = .round; p.lineJoinStyle = .round
    p.move(to: NSPoint(x:x, y:y + sy * 124))
    p.line(to: NSPoint(x:x, y:y + sy * 36))
    p.curve(to: NSPoint(x:x + sx * 36,y:y), controlPoint1:NSPoint(x:x,y:y), controlPoint2:NSPoint(x:x,y:y))
    p.line(to:NSPoint(x:x + sx * 124,y:y)); p.stroke()
}
NSColor(calibratedRed:0.663,green:0.78,blue:1,alpha:1).setFill()
NSBezierPath(ovalIn:NSRect(x:480,y:480,width:64,height:64)).fill()
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath:output))
