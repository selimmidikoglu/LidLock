// Draws the LidLock artwork — a laptop in three-quarter view with a padlock on
// its left edge — and writes it as a square tile for make-icon.swift to mask.
// Usage: swift Tools/make-logo.swift <output.png> [yaw-degrees] [paw|nopaw]

import CoreGraphics
import Foundation
import ImageIO

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

let args = CommandLine.arguments
guard (2...4).contains(args.count) else {
    fail("usage: make-logo.swift <output.png> [yaw] [paw|nopaw]")
}
let outURL = URL(fileURLWithPath: args[1])
let yawDegrees = args.count >= 3 ? Double(args[2]) ?? 45 : 45
let drawsPaw = args.count >= 4 ? args[3] != "nopaw" : true

let S = 1536.0                       // tile side
let space = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
                          bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fail("could not create context")
}
ctx.interpolationQuality = .high

// ── colour helpers ──────────────────────────────────────────────────────────
func rgb(_ hex: UInt32, _ alpha: Double = 1) -> CGColor {
    CGColor(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255, alpha: alpha)
}
func scaled(_ color: CGColor, _ factor: Double) -> CGColor {
    let c = color.components ?? [0, 0, 0, 1]
    return CGColor(red: min(1, c[0] * factor), green: min(1, c[1] * factor),
                   blue: min(1, c[2] * factor), alpha: c[3])
}
func gradient(_ colors: [CGColor], _ stops: [CGFloat]) -> CGGradient {
    guard let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: stops) else {
        fail("gradient failed")
    }
    return g
}

// ── background: the dark tile the subject sits on ───────────────────────────
ctx.saveGState()
ctx.addRect(CGRect(x: 0, y: 0, width: S, height: S))
ctx.clip()
ctx.drawRadialGradient(gradient([rgb(0x34353C), rgb(0x18191E), rgb(0x0B0B0D)], [0, 0.55, 1]),
                       startCenter: CGPoint(x: S * 0.5, y: S * 0.60), startRadius: 0,
                       endCenter: CGPoint(x: S * 0.5, y: S * 0.60), endRadius: S * 0.80,
                       options: [.drawsAfterEndLocation])
ctx.restoreGState()

// ── minimal 3-D: a yawed, slightly top-down view ────────────────────────────
struct V3 { var x, y, z: Double }
func + (a: V3, b: V3) -> V3 { V3(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z) }
func - (a: V3, b: V3) -> V3 { V3(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
func * (v: V3, s: Double) -> V3 { V3(x: v.x * s, y: v.y * s, z: v.z * s) }
func cross(_ a: V3, _ b: V3) -> V3 {
    V3(x: a.y * b.z - a.z * b.y, y: a.z * b.x - a.x * b.z, z: a.x * b.y - a.y * b.x)
}
func dot(_ a: V3, _ b: V3) -> Double { a.x * b.x + a.y * b.y + a.z * b.z }
func normalized(_ v: V3) -> V3 {
    let l = dot(v, v).squareRoot()
    return l == 0 ? v : v * (1 / l)
}

let yaw = yawDegrees * .pi / 180
let pitch = 16.0 * .pi / 180
func rotated(_ p: V3) -> V3 {
    let y = V3(x: p.x * cos(yaw) + p.z * sin(yaw), y: p.y, z: -p.x * sin(yaw) + p.z * cos(yaw))
    return V3(x: y.x, y: y.y * cos(pitch) - y.z * sin(pitch), z: y.y * sin(pitch) + y.z * cos(pitch))
}
let eye = 4.2, focal = 2.55, unit = S * 0.46
func project(_ p: V3) -> CGPoint {
    let r = rotated(p - V3(x: 0, y: 0.26, z: 0))
    let k = focal / (eye - r.z) * unit
    return CGPoint(x: r.x * k, y: r.y * k)
}

let light = normalized(V3(x: -0.42, y: 0.80, z: 0.58))
func shade(_ normal: V3) -> Double {
    let n = normalized(rotated(normal) - rotated(V3(x: 0, y: 0, z: 0)))
    return 0.40 + 0.60 * pow(max(0, dot(n, light)), 0.75)
}

struct Face { var points: [V3]; var color: CGColor; var sheen: Double; var gloss: Bool }
var faces: [Face] = []
func face(_ points: [V3], _ color: CGColor, sheen: Double = 1, gloss: Bool = false) {
    faces.append(Face(points: points, color: color, sheen: sheen, gloss: gloss))
}

// Laptop: a base slab hinged to a lid leaning 10° back.
let halfW = 0.5, depth = 0.34, slab = 0.042
let hinge = V3(x: 0, y: slab, z: -depth)
let lean = 10.0 * .pi / 180
let up = V3(x: 0, y: cos(lean), z: -sin(lean))
let out = V3(x: 0, y: sin(lean), z: cos(lean))
let lidH = 0.60, lidT = 0.026
func lid(_ u: Double, _ v: Double, _ w: Double) -> V3 {
    hinge + V3(x: u, y: 0, z: 0) + up * v + out * w
}
let alu = rgb(0xB9BEC6)

let b000 = V3(x: -halfW, y: 0, z: -depth), b100 = V3(x: halfW, y: 0, z: -depth)
let b001 = V3(x: -halfW, y: 0, z: depth), b101 = V3(x: halfW, y: 0, z: depth)
let t000 = V3(x: -halfW, y: slab, z: -depth), t100 = V3(x: halfW, y: slab, z: -depth)
let t001 = V3(x: -halfW, y: slab, z: depth), t101 = V3(x: halfW, y: slab, z: depth)
face([t000, t001, t101, t100], alu)                               // deck
face([b001, b101, t101, t001], scaled(alu, 0.80))                 // front lip
face([b000, b001, t001, t000], scaled(alu, 0.70))                 // left side
face([b101, b100, t100, t101], scaled(alu, 0.62))                 // right side

let kb = 0.05
face([V3(x: -halfW + kb, y: slab + 0.001, z: -depth + kb),
      V3(x: -halfW + kb, y: slab + 0.001, z: 0.08),
      V3(x: halfW - kb, y: slab + 0.001, z: 0.08),
      V3(x: halfW - kb, y: slab + 0.001, z: -depth + kb)], rgb(0x52565F), sheen: 0.6)
face([V3(x: -0.16, y: slab + 0.002, z: 0.13),
      V3(x: -0.16, y: slab + 0.002, z: depth - 0.05),
      V3(x: 0.16, y: slab + 0.002, z: depth - 0.05),
      V3(x: 0.16, y: slab + 0.002, z: 0.13)], rgb(0x9AA0A9), sheen: 0.85)

face([lid(-halfW, 0, 0), lid(-halfW, lidH, 0), lid(halfW, lidH, 0), lid(halfW, 0, 0)],
     scaled(alu, 0.72))                                            // back shell
face([lid(-halfW, lidH, 0), lid(-halfW, lidH, lidT), lid(halfW, lidH, lidT), lid(halfW, lidH, 0)],
     scaled(alu, 1.08))                                            // top rim
face([lid(-halfW, 0, 0), lid(-halfW, 0, lidT), lid(-halfW, lidH, lidT), lid(-halfW, lidH, 0)],
     scaled(alu, 0.68))                                            // left rim
face([lid(halfW, 0, 0), lid(halfW, lidH, 0), lid(halfW, lidH, lidT), lid(halfW, 0, lidT)],
     scaled(alu, 0.60))                                            // right rim
face([lid(-halfW, 0, lidT), lid(halfW, 0, lidT), lid(halfW, lidH, lidT), lid(-halfW, lidH, lidT)],
     rgb(0x2C2F35), sheen: 0.95)                                   // bezel
let bz = 0.032
face([lid(-halfW + bz, bz, lidT + 0.001), lid(halfW - bz, bz, lidT + 0.001),
      lid(halfW - bz, lidH - bz, lidT + 0.001), lid(-halfW + bz, lidH - bz, lidT + 0.001)],
     rgb(0x0E1014), sheen: 1.4, gloss: true)                       // screen

// ── padlock geometry, anchored to the laptop's near-left corner ─────────────
let laptopPoints = faces.flatMap { $0.points }.map(project)
let laptopBox = laptopPoints.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
let anchor = project(V3(x: -halfW, y: 0, z: depth))     // left-front bottom corner

let lockW = laptopBox.width * 0.345
let lockH = lockW * 0.82
let shackleR = lockW * 0.31, shackleT = lockW * 0.155
let body = CGRect(x: anchor.x - lockW * 0.58, y: anchor.y - lockH * 0.06,
                  width: lockW, height: lockH)
let lockBox = body.insetBy(dx: -shackleT, dy: 0)
    .union(CGRect(x: body.midX - shackleR - shackleT / 2, y: body.maxY,
                  width: (shackleR + shackleT / 2) * 2, height: shackleR + shackleT / 2))

// ── fit the whole subject into the tile ─────────────────────────────────────
let subject = laptopBox.union(lockBox)
let target = S * 0.80
let fit = target / max(subject.width, subject.height)
ctx.saveGState()
ctx.translateBy(x: S * 0.5, y: S * 0.5)
ctx.scaleBy(x: fit, y: fit)
ctx.translateBy(x: -subject.midX, y: -subject.midY)

// Contact shadow under the laptop.
ctx.saveGState()
let shadowRect = CGRect(x: laptopBox.midX - laptopBox.width * 0.50,
                        y: laptopBox.minY - laptopBox.height * 0.10,
                        width: laptopBox.width, height: laptopBox.height * 0.26)
ctx.addEllipse(in: shadowRect)
ctx.clip()
ctx.drawRadialGradient(gradient([rgb(0x000000, 0.6), rgb(0x000000, 0)], [0, 1]),
                       startCenter: CGPoint(x: shadowRect.midX, y: shadowRect.midY), startRadius: 0,
                       endCenter: CGPoint(x: shadowRect.midX, y: shadowRect.midY),
                       endRadius: shadowRect.width / 2, options: [])
ctx.restoreGState()

// Painter's algorithm over back-face-culled faces.
func depthOf(_ f: Face) -> Double {
    f.points.map { rotated($0).z }.reduce(0, +) / Double(f.points.count)
}
for f in faces.sorted(by: { depthOf($0) < depthOf($1) }) {
    let n = cross(f.points[1] - f.points[0], f.points[2] - f.points[0])
    let screenNormal = rotated(f.points[0] + n) - rotated(f.points[0])
    guard screenNormal.z > 0 else { continue }
    let lit = shade(n) * f.sheen
    let path = CGMutablePath()
    path.addLines(between: f.points.map(project))
    path.closeSubpath()
    let box = path.boundingBox
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(gradient([scaled(f.color, lit * 1.14), scaled(f.color, lit * 0.84)], [0, 1]),
                           start: CGPoint(x: box.minX, y: box.maxY),
                           end: CGPoint(x: box.maxX, y: box.minY), options: [])
    if f.gloss {
        ctx.drawLinearGradient(gradient([rgb(0xFFFFFF, 0.16), rgb(0xFFFFFF, 0.02), rgb(0xFFFFFF, 0)],
                                        [0, 0.45, 0.75]),
                               start: CGPoint(x: box.minX, y: box.maxY),
                               end: CGPoint(x: box.midX, y: box.minY), options: [])
    }
    ctx.restoreGState()
}

// ── the cat's paw, pressed against the screen ───────────────────────────────
if drawsPaw {
    // Ellipses in lid-local (across, up) coordinates, projected onto the screen.
    let pawCx = 0.0, pawCy = lidH * 0.52, k = 0.30
    let pads: [(Double, Double, Double, Double)] = [
        (0, -0.34 * k, 0.54 * k, 0.44 * k),        // main pad
        (-0.56 * k, 0.24 * k, 0.21 * k, 0.26 * k), // toes
        (-0.20 * k, 0.50 * k, 0.22 * k, 0.27 * k),
        (0.20 * k, 0.50 * k, 0.22 * k, 0.27 * k),
        (0.56 * k, 0.24 * k, 0.21 * k, 0.26 * k),
    ]
    let paw = CGMutablePath()
    for (dx, dy, rx, ry) in pads {
        var points: [CGPoint] = []
        for step in 0..<64 {
            let t = Double(step) / 64 * 2 * .pi
            points.append(project(lid(pawCx + dx + rx * cos(t), pawCy + dy + ry * sin(t),
                                      lidT + 0.002)))
        }
        paw.addLines(between: points)
        paw.closeSubpath()
    }
    let pawBox = paw.boundingBox
    ctx.saveGState()
    ctx.addPath(paw)
    ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(0xF0F3F7, 0.97), rgb(0xB9C0CB, 0.90)], [0, 1]),
                           start: CGPoint(x: pawBox.minX, y: pawBox.maxY),
                           end: CGPoint(x: pawBox.maxX, y: pawBox.minY), options: [])
    ctx.restoreGState()
}

// ── padlock, in front of the laptop's left edge ─────────────────────────────
// Contact shadow under the padlock, on the same ground plane as the laptop.
ctx.saveGState()
let lockShadow = CGRect(x: body.midX - lockW * 0.62, y: body.minY - lockH * 0.11,
                        width: lockW * 1.24, height: lockH * 0.22)
ctx.addEllipse(in: lockShadow)
ctx.clip()
ctx.drawRadialGradient(gradient([rgb(0x000000, 0.62), rgb(0x000000, 0)], [0, 1]),
                       startCenter: CGPoint(x: lockShadow.midX, y: lockShadow.midY), startRadius: 0,
                       endCenter: CGPoint(x: lockShadow.midX, y: lockShadow.midY),
                       endRadius: lockShadow.width / 2, options: [])
ctx.restoreGState()

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: -lockW * 0.05, height: -lockW * 0.07), blur: lockW * 0.20,
              color: rgb(0x000000, 0.55))
ctx.beginTransparencyLayer(auxiliaryInfo: nil)

let shacklePath = CGMutablePath()
shacklePath.addArc(center: CGPoint(x: body.midX, y: body.maxY), radius: shackleR,
                   startAngle: 0, endAngle: .pi, clockwise: false)
ctx.saveGState()
ctx.addRect(CGRect(x: body.minX - shackleR, y: body.maxY - shackleT,
                   width: body.width + shackleR * 2, height: shackleR + shackleT * 2))
ctx.clip()
ctx.setLineWidth(shackleT)
ctx.setLineCap(.round)
ctx.addPath(shacklePath)
ctx.replacePathWithStrokedPath()
ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0xEFF2F6), rgb(0x9DA3AC), rgb(0xD4D8DE), rgb(0x6E747E)],
                                [0, 0.35, 0.62, 1]),
                       start: CGPoint(x: body.minX, y: body.maxY + shackleR),
                       end: CGPoint(x: body.maxX, y: body.maxY), options: [])
ctx.restoreGState()

let bodyPath = CGPath(roundedRect: body, cornerWidth: lockW * 0.17, cornerHeight: lockW * 0.17,
                      transform: nil)
ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0xF4F6F9), rgb(0xC9CED6), rgb(0x8E949E), rgb(0xB2B8C1)],
                                [0, 0.3, 0.72, 1]),
                       start: CGPoint(x: body.minX, y: body.maxY),
                       end: CGPoint(x: body.maxX, y: body.minY), options: [])
ctx.restoreGState()
ctx.endTransparencyLayer()
ctx.restoreGState()

let keyR = lockW * 0.082
ctx.saveGState()
let keyhole = CGMutablePath()
keyhole.addEllipse(in: CGRect(x: body.midX - keyR, y: body.midY - keyR * 0.35,
                              width: keyR * 2, height: keyR * 2))
keyhole.move(to: CGPoint(x: body.midX - keyR * 0.60, y: body.midY))
keyhole.addLine(to: CGPoint(x: body.midX - keyR * 0.32, y: body.midY - keyR * 2.1))
keyhole.addLine(to: CGPoint(x: body.midX + keyR * 0.32, y: body.midY - keyR * 2.1))
keyhole.addLine(to: CGPoint(x: body.midX + keyR * 0.60, y: body.midY))
keyhole.closeSubpath()
ctx.addPath(keyhole)
ctx.setFillColor(rgb(0x2B2E34))
ctx.fillPath()
ctx.restoreGState()

ctx.restoreGState()

guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(outURL as CFURL, "public.png" as CFString, 1, nil)
else { fail("render failed") }
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fail("could not write \(outURL.path)") }
print("› wrote \(outURL.path) (yaw \(Int(yawDegrees))°)")
