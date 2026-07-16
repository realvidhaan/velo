// Renders the Velo app icon from the brand mark geometry (Velo Logo System,
// Section 02: full mark in an Apple squircle, cream #FFFDEC on charcoal #1B1B1B,
// mark ~56% of the tile). Emits a full .iconset (16→1024, incl. @2x) which the
// build's `iconutil` step turns into Resources/AppIcon.icns.
//
// The mark is pure geometry — seven rounded rects in a 196×170 viewBox — so we
// draw it directly with AppKit rather than depend on an SVG rasterizer.
//
//   swift Scripts/generate-icon.swift [outputIconsetDir]
import AppKit
import Foundation

// (x, y, w, h, cornerRadius) in the 196×170 viewBox, SVG (top-down) coordinates.
let rects: [(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, r: CGFloat)] = [
    (8, 57, 16, 56, 8),      // rising bar 1
    (40, 41, 16, 88, 8),     // rising bar 2
    (72, 24, 16, 122, 8),    // rising bar 3
    (104, 10, 16, 150, 8),   // rising bar 4 (tallest)
    (158, 10, 16, 150, 8),   // cursor shaft
    (144, 10, 44, 14, 7),    // cursor top cap
    (144, 146, 44, 14, 7),   // cursor bottom cap
]
let viewBox = CGSize(width: 196, height: 170)
let charcoal = NSColor(srgbRed: 0x1B/255, green: 0x1B/255, blue: 0x1B/255, alpha: 1)
let cream = NSColor(srgbRed: 0xFF/255, green: 0xFD/255, blue: 0xEC/255, alpha: 1)

func renderPNG(px: Int) -> Data {
    let side = CGFloat(px)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Charcoal squircle tile, full-bleed, 23% corner radius (per the spec).
    charcoal.setFill()
    NSBezierPath(roundedRect: CGRect(x: 0, y: 0, width: side, height: side),
                 xRadius: side * 0.23, yRadius: side * 0.23).fill()

    // Cream mark, 56% of the tile width, centered; preserve the 196×170 aspect.
    let markWidth = side * 0.56
    let scale = markWidth / viewBox.width
    let markHeight = viewBox.height * scale
    let originX = (side - markWidth) / 2
    let originY = (side - markHeight) / 2
    cream.setFill()
    for m in rects {
        // Convert SVG top-down y to AppKit bottom-up y.
        let y = originY + (viewBox.height - m.y - m.h) * scale
        NSBezierPath(
            roundedRect: CGRect(x: originX + m.x * scale, y: y, width: m.w * scale, height: m.h * scale),
            xRadius: m.r * scale, yRadius: m.r * scale
        ).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/Velo.iconset"
let variants: [(px: Int, name: String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"),
    (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"),
    (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x"),
]
do {
    try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
    for v in variants {
        try renderPNG(px: v.px).write(to: URL(fileURLWithPath: "\(outDir)/\(v.name).png"))
        print("wrote \(v.name).png (\(v.px)px)")
    }
} catch {
    FileHandle.standardError.write(Data("generate-icon: failed writing to \(outDir): \(error.localizedDescription)\n".utf8))
    exit(1)
}
