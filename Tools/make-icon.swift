// Crops the LidLock tile out of the source artwork, masks it to a squircle and
// writes build/LidLock.iconset + Resources/LidLock.icns.
// Usage: swift Tools/make-icon.swift <source-image> <output.icns>

import CoreGraphics
import ImageIO
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count == 3 else { fail("usage: make-icon.swift <source-image> <output.icns>") }
let sourceURL = URL(fileURLWithPath: args[1])
let icnsURL = URL(fileURLWithPath: args[2])

guard let src = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    fail("could not read \(sourceURL.path)")
}

// ── 1. Find the dark tile inside the photo ──────────────────────────────────
let w = image.width, h = image.height
var pixels = [UInt8](repeating: 0, count: w * h * 4)
let space = CGColorSpaceCreateDeviceRGB()
guard let scan = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8,
                           bytesPerRow: w * 4, space: space,
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fail("could not create scan context")
}
scan.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

var minX = w, minY = h, maxX = -1, maxY = -1
for y in 0..<h {
    for x in 0..<w {
        let i = (y * w + x) * 4
        let lum = 0.299 * Double(pixels[i]) + 0.587 * Double(pixels[i + 1]) + 0.114 * Double(pixels[i + 2])
        if lum < 115 {   // tile is near-black, background is light gray
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }
    }
}
guard maxX > minX, maxY > minY else { fail("no dark tile found in the source image") }

// Square it off around the detected centre, then shave a hair to kill any light fringe.
let side = Double(max(maxX - minX, maxY - minY) + 1)
let cx = Double(minX + maxX + 1) / 2, cy = Double(minY + maxY + 1) / 2
let inset = (side * 0.004).rounded()
let cropSide = side - inset * 2
var crop = CGRect(x: (cx - cropSide / 2).rounded(), y: (cy - cropSide / 2).rounded(),
                  width: cropSide.rounded(), height: cropSide.rounded())
crop = crop.intersection(CGRect(x: 0, y: 0, width: Double(w), height: Double(h)))
guard let tile = image.cropping(to: crop) else { fail("crop failed") }
print("› tile found at \(Int(crop.origin.x)),\(Int(crop.origin.y)) \(Int(crop.width))×\(Int(crop.height))")

// ── 2. Squircle mask (superellipse, matching Apple's icon silhouette) ───────
func squircle(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let n = 5.0                       // superellipse exponent
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    let steps = 720
    for step in 0...steps {
        let t = Double(step) / Double(steps) * 2 * Double.pi
        let ct = cos(t), st = sin(t)
        let x = cx + a * copysign(pow(abs(ct), 2 / n), ct)
        let y = cy + b * copysign(pow(abs(st), 2 / n), st)
        step == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

func context(_ size: Int) -> CGContext {
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                              bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fail("could not create \(size)px context")
    }
    ctx.interpolationQuality = .high
    return ctx
}

// Apple's macOS grid: 1024 canvas, 824 tile, 100pt margin all round for the shadow.
let canvas = 1024.0, tileSide = 824.0, margin = (canvas - tileSide) / 2

let maskCtx = context(Int(tileSide))
let tileRect = CGRect(x: 0, y: 0, width: tileSide, height: tileSide)
maskCtx.addPath(squircle(in: tileRect))
maskCtx.clip()
maskCtx.draw(tile, in: tileRect)
guard let maskedTile = maskCtx.makeImage() else { fail("masking failed") }

let iconCtx = context(Int(canvas))
iconCtx.setShadow(offset: CGSize(width: 0, height: -canvas * 0.012),
                  blur: canvas * 0.025,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.33))
iconCtx.draw(maskedTile, in: CGRect(x: margin, y: margin, width: tileSide, height: tileSide))
guard let master = iconCtx.makeImage() else { fail("compositing failed") }

// ── 3. Write the iconset and convert it ─────────────────────────────────────
let iconsetURL = icnsURL.deletingLastPathComponent()
    .appendingPathComponent(icnsURL.deletingPathExtension().lastPathComponent + ".iconset")
try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

func writePNG(_ img: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        fail("could not write \(url.lastPathComponent)")
    }
    CGImageDestinationAddImage(dest, img, nil)
    guard CGImageDestinationFinalize(dest) else { fail("could not finalize \(url.lastPathComponent)") }
}

func resized(_ img: CGImage, to size: Int) -> CGImage {
    if size == img.width { return img }
    let ctx = context(size)
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: size, height: size))
    guard let out = ctx.makeImage() else { fail("resize to \(size) failed") }
    return out
}

for base in [16, 32, 128, 256, 512] {
    writePNG(resized(master, to: base), to: iconsetURL.appendingPathComponent("icon_\(base)x\(base).png"))
    writePNG(resized(master, to: base * 2), to: iconsetURL.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
writePNG(master, to: icnsURL.deletingPathExtension().appendingPathExtension("png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fail("iconutil failed") }
print("› wrote \(icnsURL.path)")
