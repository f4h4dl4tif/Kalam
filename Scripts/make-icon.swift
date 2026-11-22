import AppKit
// Kalam icon: a fountain-pen nib in ink teal on warm paper.
let out = CommandLine.arguments[1]
let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let rect = NSRect(x: 100, y: 100, width: 824, height: 824)
let bg = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(srgbRed: 0.99, green: 0.97, blue: 0.93, alpha: 1),
                    NSColor(srgbRed: 0.94, green: 0.90, blue: 0.82, alpha: 1)])!.draw(in: bg, angle: -90)
// Faint ruled lines
NSColor(srgbRed: 0.18, green: 0.43, blue: 0.45, alpha: 0.10).setStroke()
for y in stride(from: 260.0, through: 760.0, by: 100.0) {
    let l = NSBezierPath(); l.move(to: NSPoint(x: 190, y: y)); l.line(to: NSPoint(x: 834, y: y)); l.lineWidth = 6; l.stroke()
}
// Nib
let ink = NSColor(srgbRed: 0.18, green: 0.43, blue: 0.45, alpha: 1)
let nib = NSBezierPath()
nib.move(to: NSPoint(x: 512, y: 215))            // tip
nib.curve(to: NSPoint(x: 330, y: 560), controlPoint1: NSPoint(x: 430, y: 330), controlPoint2: NSPoint(x: 330, y: 450))
nib.line(to: NSPoint(x: 390, y: 800))
nib.line(to: NSPoint(x: 634, y: 800))
nib.line(to: NSPoint(x: 694, y: 560))
nib.curve(to: NSPoint(x: 512, y: 215), controlPoint1: NSPoint(x: 694, y: 450), controlPoint2: NSPoint(x: 594, y: 330))
nib.close()
NSGradient(colors: [ink, NSColor(srgbRed: 0.11, green: 0.31, blue: 0.33, alpha: 1)])!.draw(in: nib, angle: -90)
// Slit and breather hole
let paper = NSColor(srgbRed: 0.97, green: 0.94, blue: 0.88, alpha: 1)
paper.setStroke()
let slit = NSBezierPath(); slit.move(to: NSPoint(x: 512, y: 240)); slit.line(to: NSPoint(x: 512, y: 520)); slit.lineWidth = 16; slit.lineCapStyle = .round; slit.stroke()
paper.setFill()
NSBezierPath(ovalIn: NSRect(x: 477, y: 515, width: 70, height: 70)).fill()
// Collar
NSColor(srgbRed: 0.11, green: 0.31, blue: 0.33, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 372, y: 790, width: 280, height: 56), xRadius: 18, yRadius: 18).fill()
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
