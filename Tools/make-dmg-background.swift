// Draws the backdrop of the disk image window: the dark field the app icon and
// the Applications alias sit on, with an arrow pointing from one to the other.
//   swift Tools/make-dmg-background.swift <out-dir>
// Writes background.png and background@2x.png, which make-dmg.sh folds into a
// single TIFF so Finder picks the right one per display.

import CoreGraphics
import CoreText
import Foundation
import ImageIO

#if canImport(AppKit)
import AppKit
#endif

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let space = CGColorSpaceCreateDeviceRGB()

func rgb(_ hex: UInt32, _ alpha: Double = 1) -> CGColor {
    CGColor(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255, alpha: alpha)
}

/// 640×400 of window, drawn at `scale` so Finder has a crisp copy either way.
func render(scale: Double) -> CGImage {
    let w = 640.0, h = 400.0
    guard let ctx = CGContext(data: nil, width: Int(w * scale), height: Int(h * scale),
                              bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fail("could not create context")
    }
    ctx.scaleBy(x: scale, y: scale)
    ctx.interpolationQuality = .high

    ctx.setFillColor(rgb(0x121214))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    if let gradient = CGGradient(colorsSpace: space,
                                 colors: [rgb(0x2C2D33), rgb(0x121214, 0)] as CFArray,
                                 locations: [0, 1]) {
        ctx.drawRadialGradient(gradient,
                               startCenter: CGPoint(x: w / 2, y: h * 0.62), startRadius: 0,
                               endCenter: CGPoint(x: w / 2, y: h * 0.62), endRadius: w * 0.62,
                               options: [])
    }

    // The arrow runs between the two icons, which sit at y = 230 from the top.
    let y = h - 230.0
    let start = 250.0, end = 390.0
    ctx.setStrokeColor(rgb(0x6E7480))
    ctx.setLineWidth(3)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: start, y: y))
    ctx.addLine(to: CGPoint(x: end - 14, y: y))
    ctx.strokePath()

    ctx.setFillColor(rgb(0x6E7480))
    ctx.move(to: CGPoint(x: end, y: y))
    ctx.addLine(to: CGPoint(x: end - 18, y: y + 11))
    ctx.addLine(to: CGPoint(x: end - 18, y: y - 11))
    ctx.closePath()
    ctx.fillPath()

    func text(_ string: String, size: Double, color: CGColor, baseline: Double) {
        let font = CTFontCreateUIFontForLanguage(.system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: string,
            attributes: [.font: font, .foregroundColor: color]
        ) as CFAttributedString)
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        ctx.textPosition = CGPoint(x: (w - width) / 2, y: baseline)
        CTLineDraw(line, ctx)
    }

    text("Drag LidLock into your Applications folder", size: 17, color: rgb(0xE8EAEE),
         baseline: h - 92)
    text("Opening it from here leaves macOS running a temporary copy.",
         size: 12, color: rgb(0x8C919B), baseline: h - 118)

    guard let image = ctx.makeImage() else { fail("render failed") }
    return image
}

for (scale, name) in [(1.0, "background.png"), (2.0, "background@2x.png")] {
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
    else { fail("could not write \(name)") }
    CGImageDestinationAddImage(dest, render(scale: scale), nil)
    guard CGImageDestinationFinalize(dest) else { fail("could not finalize \(name)") }
    print("› wrote \(url.path)")
}
