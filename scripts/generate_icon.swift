#!/usr/bin/env swift
import AppKit

func createIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    let ctx = NSGraphicsContext.current!.cgContext

    // Background: rounded rect with gradient (deep purple to dark blue)
    let radius = s * 0.22
    let bgPath = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                        cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(bgPath)
    ctx.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        CGColor(red: 0.28, green: 0.15, blue: 0.65, alpha: 1.0),  // #4826A6
        CGColor(red: 0.11, green: 0.10, blue: 0.18, alpha: 1.0),  // #1C1A2E
    ]
    let gradient = CGGradient(colorsSpace: colorSpace, colors: bgColors as CFArray, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: s/2, y: s), end: CGPoint(x: s/2, y: 0), options: [])

    // Subtle inner glow
    ctx.resetClip()

    // Microphone body (center)
    let micW = s * 0.18
    let micH = s * 0.30
    let micX = s/2 - micW/2
    let micY = s * 0.42
    let micRect = CGRect(x: micX, y: micY, width: micW, height: micH)
    let micPath = CGPath(roundedRect: micRect, cornerWidth: micW/2, cornerHeight: micW/2, transform: nil)

    // Mic gradient (bright purple to lighter)
    ctx.addPath(micPath)
    ctx.clip()
    let micColors = [
        CGColor(red: 0.65, green: 0.45, blue: 0.96, alpha: 1.0),  // #A673F5
        CGColor(red: 0.49, green: 0.36, blue: 0.96, alpha: 1.0),  // #7C5BF6
    ]
    let micGradient = CGGradient(colorsSpace: colorSpace, colors: micColors as CFArray, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(micGradient,
                           start: CGPoint(x: s/2, y: micY + micH),
                           end: CGPoint(x: s/2, y: micY),
                           options: [])
    ctx.resetClip()

    // Mic grille lines
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.15))
    ctx.setLineWidth(s * 0.008)
    for i in 1...3 {
        let y = micY + micH * 0.3 + CGFloat(i) * micH * 0.15
        ctx.move(to: CGPoint(x: micX + micW * 0.25, y: y))
        ctx.addLine(to: CGPoint(x: micX + micW * 0.75, y: y))
    }
    ctx.strokePath()

    // Mic arc (U shape below mic)
    let arcRadius = s * 0.16
    let arcCenter = CGPoint(x: s/2, y: micY + micH * 0.15)
    ctx.setStrokeColor(CGColor(red: 0.65, green: 0.45, blue: 0.96, alpha: 0.7))
    ctx.setLineWidth(s * 0.025)
    ctx.setLineCap(.round)
    ctx.addArc(center: arcCenter, radius: arcRadius, startAngle: 0, endAngle: .pi, clockwise: false)
    ctx.strokePath()

    // Mic stand (vertical line + base)
    let standTop = arcCenter.y - arcRadius
    let standBottom = s * 0.22
    ctx.setStrokeColor(CGColor(red: 0.65, green: 0.45, blue: 0.96, alpha: 0.7))
    ctx.setLineWidth(s * 0.025)
    ctx.move(to: CGPoint(x: s/2, y: standTop))
    ctx.addLine(to: CGPoint(x: s/2, y: standBottom))
    ctx.strokePath()

    // Base horizontal
    ctx.move(to: CGPoint(x: s/2 - s * 0.08, y: standBottom))
    ctx.addLine(to: CGPoint(x: s/2 + s * 0.08, y: standBottom))
    ctx.strokePath()

    // Waveform bars (left side)
    let barColor = CGColor(red: 0.42, green: 0.78, blue: 1.0, alpha: 0.8)  // Blue
    ctx.setFillColor(barColor)
    let barW = s * 0.028
    let barSpacing = s * 0.045
    let barCenterY = s * 0.55
    let leftBars: [CGFloat] = [0.08, 0.15, 0.22, 0.12, 0.06]

    for (i, h) in leftBars.enumerated() {
        let barH = s * h
        let x = s * 0.12 + CGFloat(i) * barSpacing
        let y = barCenterY - barH/2
        let barRect = CGRect(x: x, y: y, width: barW, height: barH)
        let barPath = CGPath(roundedRect: barRect, cornerWidth: barW/2, cornerHeight: barW/2, transform: nil)
        ctx.addPath(barPath)
    }
    ctx.fillPath()

    // Waveform bars (right side)
    let rightBars: [CGFloat] = [0.06, 0.12, 0.22, 0.15, 0.08]
    for (i, h) in rightBars.enumerated() {
        let barH = s * h
        let x = s * 0.65 + CGFloat(i) * barSpacing
        let y = barCenterY - barH/2
        let barRect = CGRect(x: x, y: y, width: barW, height: barH)
        let barPath = CGPath(roundedRect: barRect, cornerWidth: barW/2, cornerHeight: barW/2, transform: nil)
        ctx.addPath(barPath)
    }
    ctx.fillPath()

    image.unlockFocus()
    return image
}

// Generate iconset
let iconsetPath = "/Users/cagdas/CodTemp/claude-code-handsfree/Resources/AppIcon.iconset"
let fm = FileManager.default
try? fm.removeItem(atPath: iconsetPath)
try! fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for (size, name) in sizes {
    let img = createIcon(size: size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                isPlanar: false, colorSpaceName: .deviceRGB,
                                bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()

    let data = rep.representation(using: .png, properties: [:])!
    let path = "\(iconsetPath)/\(name)"
    try! data.write(to: URL(fileURLWithPath: path))
}

print("Iconset generated at \(iconsetPath)")
