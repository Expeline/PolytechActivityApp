import AppKit
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
let hues: [String: CGFloat] = ["green": 0.39, "blue": 0.60, "purple": 0.75, "pink": 0.91, "red": 0, "orange": 0.075, "yellow": 0.13, "teal": 0.49, "graphite": 0.60]
let accent = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "green"
let hue = hues[accent] ?? 0.39
let gray = accent == "graphite"
let background = accent == "green" ? NSColor(srgbRed: 0.035, green: 0.12, blue: 0.095, alpha: 1) : NSColor(hue: hue, saturation: gray ? 0.12 : 0.67, brightness: 0.25, alpha: 1)
background.setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()
let mint = accent == "green" ? NSColor(srgbRed: 0.76, green: 0.94, blue: 0.54, alpha: 1) : NSColor(hue: hue, saturation: gray ? 0.06 : 0.30, brightness: 0.98, alpha: 1)
mint.setFill()
// Original geometric monogram: an open book and two upward steps.
let book = NSBezierPath()
book.move(to: NSPoint(x: 238, y: 725))
book.line(to: NSPoint(x: 464, y: 663))
book.line(to: NSPoint(x: 464, y: 276))
book.line(to: NSPoint(x: 238, y: 338))
book.close(); book.fill()
let right = NSBezierPath()
right.move(to: NSPoint(x: 535, y: 663))
right.line(to: NSPoint(x: 786, y: 725))
right.line(to: NSPoint(x: 786, y: 595))
right.line(to: NSPoint(x: 656, y: 561))
right.line(to: NSPoint(x: 656, y: 326))
right.line(to: NSPoint(x: 535, y: 276))
right.close(); right.fill()
NSColor(hue: hue, saturation: gray ? 0.08 : 0.45, brightness: 0.7, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 710, y: 330, width: 76, height: 176), xRadius: 14, yRadius: 14).fill()
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
