// Draws the app icon: a flashcard whose highlighted line becomes a new card.
// Usage: swift Resources/make-icon.swift <output.png>   (1024×1024)
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

/// Runs `draw` with the context rotated by `degrees` around `center`.
func rotated(_ degrees: CGFloat, around center: CGPoint, _ draw: () -> Void) {
    let t = NSAffineTransform()
    t.translateX(by: center.x, yBy: center.y)
    t.rotate(byDegrees: degrees)
    t.translateX(by: -center.x, yBy: -center.y)
    NSGraphicsContext.saveGraphicsState()
    t.concat()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

func withShadow(blur: CGFloat, offsetY: CGFloat, alpha: CGFloat, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = NSSize(width: 0, height: offsetY)
    shadow.shadowColor = NSColor.black.withAlphaComponent(alpha)
    shadow.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Background tile, inset like Apple's macOS icon grid (824 of 1024).
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
withShadow(blur: 28, offsetY: -12, alpha: 0.35) {
    color(0x3D5AFE).setFill()
    roundedRect(tile, 185).fill()
}
NSGradient(colors: [color(0x5B8CFF), color(0x3A4FE0), color(0x2A2F9E)],
           atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
    .draw(in: roundedRect(tile, 185), angle: -90)
// Soft light from the top.
NSGradient(colors: [NSColor.white.withAlphaComponent(0.18), NSColor.white.withAlphaComponent(0)])!
    .draw(in: roundedRect(tile.insetBy(dx: 6, dy: 6), 180), angle: -90)

// Card behind, tilted left.
let back = CGRect(x: 250, y: 430, width: 500, height: 330)
rotated(9, around: CGPoint(x: back.midX, y: back.midY)) {
    withShadow(blur: 22, offsetY: -8, alpha: 0.25) {
        color(0xDCE4FF).setFill()
        roundedRect(back, 44).fill()
    }
}

// Front card with text lines; the middle line is highlighted (the selection).
let front = CGRect(x: 230, y: 290, width: 560, height: 370)
rotated(-4, around: CGPoint(x: front.midX, y: front.midY)) {
    withShadow(blur: 30, offsetY: -14, alpha: 0.3) {
        NSColor.white.setFill()
        roundedRect(front, 48).fill()
    }
    let left = front.minX + 62
    let lineHeight: CGFloat = 34
    let gray = color(0xC9CFDC)
    gray.setFill()
    roundedRect(CGRect(x: left, y: front.maxY - 100, width: 400, height: lineHeight), 17).fill()
    // highlighted selection
    color(0xFFD43B).setFill()
    roundedRect(CGRect(x: left - 16, y: front.midY - 38, width: 360, height: 76), 22).fill()
    color(0x2B3170).setFill()
    roundedRect(CGRect(x: left, y: front.midY - lineHeight / 2, width: 328, height: lineHeight), 17).fill()
    gray.setFill()
    roundedRect(CGRect(x: left, y: front.minY + 66, width: 300, height: lineHeight), 17).fill()
}

// Green "+" badge: add to Anki.
let badgeCenter = CGPoint(x: 742, y: 300)
let badgeRadius: CGFloat = 112
withShadow(blur: 24, offsetY: -10, alpha: 0.35) {
    color(0x30C85A).setFill()
    NSBezierPath(ovalIn: CGRect(x: badgeCenter.x - badgeRadius, y: badgeCenter.y - badgeRadius,
                                width: badgeRadius * 2, height: badgeRadius * 2)).fill()
}
NSColor.white.withAlphaComponent(0.9).setStroke()
let ring = NSBezierPath(ovalIn: CGRect(x: badgeCenter.x - badgeRadius, y: badgeCenter.y - badgeRadius,
                                       width: badgeRadius * 2, height: badgeRadius * 2))
ring.lineWidth = 14
ring.stroke()
NSColor.white.setFill()
let arm: CGFloat = 58, thick: CGFloat = 30
roundedRect(CGRect(x: badgeCenter.x - arm, y: badgeCenter.y - thick / 2, width: arm * 2, height: thick), thick / 2).fill()
roundedRect(CGRect(x: badgeCenter.x - thick / 2, y: badgeCenter.y - arm, width: thick, height: arm * 2), thick / 2).fill()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("Icon: \(output)")
