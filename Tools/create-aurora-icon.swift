import AppKit

// Original vector artwork for Aurora. Drawn with AppKit; no external images or fonts.
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AuroraIcon.png"
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
bitmap.size = NSSize(width: 1024, height: 1024)
let context = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.shouldAntialias = true
func c(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}
func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat, _ color: UInt32) {
    c(color).setFill(); NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r).fill()
}
func ellipse(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: UInt32) {
    c(color).setFill(); NSBezierPath(ovalIn: NSRect(x: x, y: y, width: w, height: h)).fill()
}
func line(_ points: [NSPoint], _ color: UInt32, _ width: CGFloat) {
    let p = NSBezierPath(); p.lineWidth = width; p.lineCapStyle = .round; p.lineJoinStyle = .round
    p.move(to: points[0]); for point in points.dropFirst() { p.line(to: point) }; c(color).setStroke(); p.stroke()
}
func curve(_ start: NSPoint, _ control1: NSPoint, _ control2: NSPoint, _ end: NSPoint, _ color: UInt32, _ width: CGFloat) {
    let p = NSBezierPath(); p.lineWidth = width; p.lineCapStyle = .round
    p.move(to: start); p.curve(to: end, controlPoint1: control1, controlPoint2: control2); c(color).setStroke(); p.stroke()
}
// A softly rounded room, with a quiet window and a simple desk silhouette.
rounded(72, 72, 880, 880, 210, 0xEEE0C9)
rounded(108, 108, 808, 808, 178, 0xF8ECDD)
rounded(194, 516, 338, 276, 34, 0xC8D4C1)
rounded(211, 533, 304, 242, 22, 0xE3EBDF)
ellipse(380, 641, 91, 91, 0xE6AC83)
rounded(211, 533, 304, 59, 0, 0xBED0BB)
line([NSPoint(x: 365, y: 536), NSPoint(x: 365, y: 772)], 0xF8ECDD, 13)
line([NSPoint(x: 215, y: 647), NSPoint(x: 513, y: 647)], 0xF8ECDD, 13)
// Plant: drawn as clear, quiet shapes rather than a detailed picture.
curve(NSPoint(x: 719,y: 531), NSPoint(x: 719,y: 588), NSPoint(x: 719,y: 645), NSPoint(x: 719,y: 689), 0x687E63, 13)
curve(NSPoint(x: 718,y: 579), NSPoint(x: 683,y: 601), NSPoint(x: 671,y: 632), NSPoint(x: 671,y: 654), 0x687E63, 12)
curve(NSPoint(x: 721,y: 600), NSPoint(x: 752,y: 619), NSPoint(x: 768,y: 646), NSPoint(x: 771,y: 668), 0x687E63, 12)
ellipse(649, 626, 52, 89, 0x9CB194)
ellipse(744, 642, 52, 89, 0x8EA98A)
ellipse(694, 672, 50, 90, 0xA8BE9F)
rounded(669, 499, 101, 78, 20, 0xC9896A)
rounded(659, 557, 121, 19, 9, 0xB9795F)
// Desk and drawer.
rounded(167, 420, 690, 57, 25, 0xA66D53)
rounded(190, 210, 644, 220, 29, 0xC8926F)
rounded(215, 230, 594, 175, 20, 0xDBAC88)
rounded(351, 307, 322, 69, 14, 0xF1D8BD)
rounded(476, 335, 72, 12, 6, 0xB97D62)
// Open notebook and a small cup on the desk.
rounded(309, 472, 252, 42, 8, 0xFEF9EE)
line([NSPoint(x: 435,y: 476), NSPoint(x: 435,y: 510)], 0xD7C6AF, 5)
line([NSPoint(x: 330,y: 500), NSPoint(x: 409,y: 500)], 0xD9C9B3, 4)
line([NSPoint(x: 460,y: 500), NSPoint(x: 539,y: 500)], 0xD9C9B3, 4)
rounded(597, 472, 64, 52, 13, 0xF8F4E8)
let handle = NSBezierPath(ovalIn: NSRect(x: 646, y: 480, width: 37, height: 30)); handle.lineWidth = 8; c(0xF8F4E8).setStroke(); handle.stroke()
NSGraphicsContext.restoreGraphicsState()
let png = bitmap.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: output))
