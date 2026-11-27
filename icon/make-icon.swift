// Draws the VOHover app icon: a pointer with sound waves radiating from its tip.
//   swift icon/make-icon.swift [output.icns] [--preview preview.png] [--style blue|charcoal]
// Writes AppIcon.icns (all sizes drawn as vectors, so small sizes stay sharp).

import AppKit

var args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    defer { args.removeSubrange(i...i + 1) }
    return args[i + 1]
}
let preview = option("--preview")
let style = option("--style") ?? "blue"
let output = args.first ?? "AppIcon.icns"

let (top, bottom, waveColor): (NSColor, NSColor, NSColor) = style == "charcoal"
    ? (NSColor(srgbRed: 0.24, green: 0.25, blue: 0.32, alpha: 1), NSColor(srgbRed: 0.07, green: 0.07, blue: 0.10, alpha: 1),
       NSColor(srgbRed: 0.50, green: 0.64, blue: 1.00, alpha: 1))
    : (NSColor(srgbRed: 0.40, green: 0.53, blue: 1.00, alpha: 1), NSColor(srgbRed: 0.17, green: 0.20, blue: 0.66, alpha: 1),
       .white)
let outlineColor = NSColor(srgbRed: 0.08, green: 0.09, blue: 0.20, alpha: 1)

/// Draws the icon in a 1024 x 1024 space (y down), following the macOS icon grid:
/// an 824-point rounded square, inset 100 points, with a soft shadow.
func drawIcon() {
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 20
    shadow.set()
    top.setFill(); shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: top, ending: bottom)!.draw(in: shape, angle: 90)

    // The glyph is designed on an 18-unit grid (the size of a menu bar icon) and scaled up.
    let k: CGFloat = 36
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: 512 + (x - 7.5) * k, y: 512 + (y - 8.9) * k) }
    let tip = (x: CGFloat(7.5), y: CGFloat(7))

    NSGraphicsContext.saveGraphicsState()
    let glyphShadow = NSShadow()
    glyphShadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    glyphShadow.shadowOffset = NSSize(width: 0, height: -8)
    glyphShadow.shadowBlurRadius = 14
    glyphShadow.set()

    // Waves around the tip, leaving a gap where the pointer is (angles clockwise from the right).
    waveColor.setStroke()
    for r: CGFloat in [3.3, 6.0] {
        let wave = NSBezierPath()
        wave.appendArc(withCenter: p(tip.x, tip.y), radius: r * k, startAngle: 120, endAngle: 370, clockwise: false)
        wave.lineWidth = 1.3 * k
        wave.lineCapStyle = .round
        wave.stroke()
    }

    // Classic arrow pointer, 52 x 82 units from its tip: white with a dark outline.
    let s: CGFloat = 0.125
    let outline: [(CGFloat, CGFloat)] = [(0, 0), (0, 72), (17, 56), (28, 82), (40, 77), (29, 52), (52, 52)]
    let pointer = NSBezierPath()
    for (i, (x, y)) in outline.enumerated() {
        let q = p(tip.x + x * s, tip.y + y * s)
        if i == 0 { pointer.move(to: q) } else { pointer.line(to: q) }
    }
    pointer.close()
    pointer.lineJoinStyle = .round
    pointer.lineWidth = 0.45 * k
    outlineColor.setStroke(); pointer.stroke()
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.setFill(); pointer.fill()
}

func render(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let scale = CGFloat(px) / 1024
    ctx.cgContext.translateBy(x: 0, y: CGFloat(px))
    ctx.cgContext.scaleBy(x: scale, y: -scale)   // y down, 1024-point space
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func png(_ rep: NSBitmapImageRep) -> Data { rep.representation(using: .png, properties: [:])! }

let iconset = FileManager.default.temporaryDirectory.appending(path: "AppIcon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try png(render(size)).write(to: iconset.appending(path: "icon_\(size)x\(size).png"))
    try png(render(size * 2)).write(to: iconset.appending(path: "icon_\(size)x\(size)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", "-o", output, iconset.path]
try iconutil.run(); iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote \(output)")
if let preview { try png(render(1024)).write(to: URL(fileURLWithPath: preview)); print("Wrote \(preview)") }
