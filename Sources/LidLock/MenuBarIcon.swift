import AppKit

/// The status bar glyph: a laptop with a paw pressed into its screen.
///
/// Drawn rather than loaded so it stays a template image — macOS tints it for
/// the light, dark and tinted menu bars, and no asset has to ship in the bundle.
enum MenuBarIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()

            let lid = NSBezierPath(roundedRect: NSRect(x: 3.4, y: 6.1, width: 11.2, height: 9.2),
                                   xRadius: 1.5, yRadius: 1.5)
            lid.lineWidth = 1.45
            lid.stroke()

            NSBezierPath(roundedRect: NSRect(x: 1.0, y: 3.2, width: 16.0, height: 1.9),
                         xRadius: 0.95, yRadius: 0.95).fill()

            let pads: [(x: Double, y: Double, rx: Double, ry: Double)] = [
                (9.0, 9.4, 1.95, 1.5),      // main pad
                (6.75, 11.3, 0.82, 1.0),    // toes
                (8.15, 12.5, 0.86, 1.05),
                (9.85, 12.5, 0.86, 1.05),
                (11.25, 11.3, 0.82, 1.0),
            ]
            let paw = NSBezierPath()
            for pad in pads {
                paw.appendOval(in: NSRect(x: pad.x - pad.rx, y: pad.y - pad.ry,
                                          width: pad.rx * 2, height: pad.ry * 2))
            }
            paw.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
