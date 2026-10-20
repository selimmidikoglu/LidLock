import SwiftUI

/// The cat knight: drawn with shapes rather than shipped as an image, so it
/// stays crisp on every display and the app stays a single binary.
///
/// Everything is laid out on a 200×200 grid and scaled to fit, so the only
/// number that ever needs changing is the frame it is given.
struct CatKnight: View {
    /// Seconds since the lock began, which is all the animation needs.
    let time: TimeInterval

    private let steelRamp = Gradient(colors: [Color(white: 0.80), Color(white: 0.50), Color(white: 0.68)])
    private let darkRamp = Gradient(colors: [Color(white: 0.42), Color(white: 0.24)])

    /// Lights a shape from its own upper left, so every piece of armour catches
    /// the light from the same direction without hand-placing gradient stops.
    private func steel(_ bounds: CGRect) -> GraphicsContext.Shading {
        .linearGradient(
            steelRamp,
            startPoint: CGPoint(x: bounds.minX, y: bounds.minY),
            endPoint: CGPoint(x: bounds.maxX, y: bounds.maxY)
        )
    }

    private func darkSteel(_ bounds: CGRect) -> GraphicsContext.Shading {
        .linearGradient(
            darkRamp,
            startPoint: CGPoint(x: bounds.midX, y: bounds.minY),
            endPoint: CGPoint(x: bounds.midX, y: bounds.maxY)
        )
    }

    private var bob: CGFloat { sin(time * 1.9) * 3 }
    private var tailSwing: Double { sin(time * 1.4) * 22 }
    private var swordSway: Double { sin(time * 1.1) * 4 }
    /// Open most of the time, shut for a blink every few seconds.
    private var eyeOpening: CGFloat {
        let cycle = time.truncatingRemainder(dividingBy: 4.2)
        guard cycle > 3.95 else { return 1 }
        return CGFloat(abs(cycle - 4.075) / 0.125)
    }

    var body: some View {
        Canvas { context, size in
            // Drawn on a 200×200 grid, then inset so the armour never touches
            // the edge of whatever frame the view is given.
            let scale = min(size.width, size.height) / 200 * 0.92
            context.translateBy(x: size.width / 2, y: size.height / 2)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -100, y: -100)

            draw(tail: &context)
            draw(sword: &context)
            draw(body: &context)
            draw(shield: &context)
            draw(helm: &context)
        }
    }

    // MARK: - Pieces

    private func draw(tail context: inout GraphicsContext) {
        var tail = Path()
        tail.move(to: CGPoint(x: 128, y: 176 + bob))
        tail.addCurve(
            to: CGPoint(x: 186, y: 146 + bob),
            control1: CGPoint(x: 166, y: 190 + bob),
            control2: CGPoint(x: 190 + tailSwing * 0.35, y: 178 + bob)
        )
        context.stroke(
            tail,
            with: .linearGradient(
                Gradient(colors: [Color(white: 0.26), Color(white: 0.44)]),
                startPoint: CGPoint(x: 128, y: 180),
                endPoint: CGPoint(x: 188, y: 142)
            ),
            style: StrokeStyle(lineWidth: 8.5, lineCap: .round)
        )
    }

    private func draw(sword context: inout GraphicsContext) {
        var blade = Path()
        blade.move(to: CGPoint(x: 158, y: 18 + bob))
        blade.addLine(to: CGPoint(x: 168, y: 38 + bob))
        blade.addLine(to: CGPoint(x: 168, y: 112 + bob))
        blade.addLine(to: CGPoint(x: 148, y: 112 + bob))
        blade.addLine(to: CGPoint(x: 148, y: 38 + bob))
        blade.closeSubpath()

        var guardBar = Path(roundedRect: CGRect(x: 136, y: 110 + bob, width: 44, height: 9), cornerRadius: 4)
        var grip = Path(roundedRect: CGRect(x: 153, y: 118 + bob, width: 10, height: 24), cornerRadius: 4)
        var pommel = Path(ellipseIn: CGRect(x: 151, y: 139 + bob, width: 14, height: 14))

        // The whole sword leans together, pivoting where the paw holds it.
        let pivot = CGPoint(x: 158, y: 126 + bob)
        let lean = CGAffineTransform(translationX: pivot.x, y: pivot.y)
            .rotated(by: swordSway * .pi / 180)
            .translatedBy(x: -pivot.x, y: -pivot.y)
        blade = blade.applying(lean)
        guardBar = guardBar.applying(lean)
        grip = grip.applying(lean)
        pommel = pommel.applying(lean)

        context.fill(blade, with: .linearGradient(
            Gradient(colors: [Color(white: 0.92), Color(white: 0.58)]),
            startPoint: CGPoint(x: 150, y: 26),
            endPoint: CGPoint(x: 172, y: 120)
        ))
        context.fill(guardBar, with: .color(Color(red: 0.72, green: 0.56, blue: 0.26)))
        context.fill(grip, with: .color(Color(red: 0.34, green: 0.20, blue: 0.14)))
        context.fill(pommel, with: .color(Color(red: 0.76, green: 0.60, blue: 0.28)))

        // The gauntlet paw wrapped around the grip — without it the sword reads
        // as floating next to the knight rather than being carried by it.
        let paw = Path(ellipseIn: CGRect(x: 142, y: 118 + bob, width: 30, height: 25).applying(lean))
        context.fill(paw, with: steel(paw.boundingRect))
        context.stroke(paw, with: .color(.black.opacity(0.35)), lineWidth: 1.5)
        for offset in [0.0, 8.0, 16.0] {
            let knuckle = Path(ellipseIn: CGRect(x: 145 + offset, y: 121 + bob, width: 7, height: 7).applying(lean))
            context.fill(knuckle, with: .color(.white.opacity(0.13)))
        }
    }

    private func draw(body context: inout GraphicsContext) {
        var torso = Path()
        torso.move(to: CGPoint(x: 68, y: 134 + bob))
        torso.addLine(to: CGPoint(x: 132, y: 134 + bob))
        torso.addQuadCurve(to: CGPoint(x: 136, y: 174 + bob), control: CGPoint(x: 145, y: 152 + bob))
        torso.addQuadCurve(to: CGPoint(x: 64, y: 174 + bob), control: CGPoint(x: 100, y: 196 + bob))
        torso.addQuadCurve(to: CGPoint(x: 68, y: 134 + bob), control: CGPoint(x: 55, y: 152 + bob))
        context.fill(torso, with: darkSteel(torso.boundingRect))

        for x in [63.0, 137.0] {
            let pauldron = Path(ellipseIn: CGRect(x: x - 21, y: 124 + bob, width: 42, height: 30))
            context.fill(pauldron, with: steel(pauldron.boundingRect))
            context.stroke(pauldron, with: .color(.black.opacity(0.38)), lineWidth: 1.5)
            let ridge = Path(ellipseIn: CGRect(x: x - 13, y: 128 + bob, width: 26, height: 16))
            context.stroke(ridge, with: .color(.black.opacity(0.16)), lineWidth: 1.2)
        }
    }

    private func draw(shield context: inout GraphicsContext) {
        var shield = Path()
        shield.move(to: CGPoint(x: 22, y: 124 + bob))
        shield.addLine(to: CGPoint(x: 74, y: 124 + bob))
        shield.addQuadCurve(to: CGPoint(x: 48, y: 190 + bob), control: CGPoint(x: 74, y: 171 + bob))
        shield.addQuadCurve(to: CGPoint(x: 22, y: 124 + bob), control: CGPoint(x: 22, y: 171 + bob))
        context.fill(shield, with: .linearGradient(
            Gradient(colors: [Color(red: 0.55, green: 0.17, blue: 0.20), Color(red: 0.33, green: 0.09, blue: 0.12)]),
            startPoint: CGPoint(x: 22, y: 124),
            endPoint: CGPoint(x: 74, y: 190)
        ))
        context.stroke(shield, with: steel(shield.boundingRect), lineWidth: 3.5)

        // Paw print blazon.
        let pad = Path(ellipseIn: CGRect(x: 38, y: 154 + bob, width: 21, height: 18))
        context.fill(pad, with: .color(Color(white: 0.93).opacity(0.92)))
        for (dx, dy, size) in [(-0.5, 0.0, 7.0), (7.5, -4.0, 7.5), (16.0, 0.5, 7.0)] {
            let toe = Path(ellipseIn: CGRect(x: 37 + dx, y: 142 + dy + bob, width: size, height: size + 1))
            context.fill(toe, with: .color(Color(white: 0.93).opacity(0.92)))
        }
    }

    private func draw(helm context: inout GraphicsContext) {
        // Ears first, so the helm overlaps their base.
        for (tip, left, right, flip) in [
            (CGPoint(x: 64, y: 22), CGPoint(x: 56, y: 62), CGPoint(x: 88, y: 56), false),
            (CGPoint(x: 136, y: 22), CGPoint(x: 112, y: 56), CGPoint(x: 144, y: 62), true),
        ] {
            var ear = Path()
            ear.move(to: CGPoint(x: tip.x, y: tip.y + bob))
            ear.addLine(to: CGPoint(x: left.x, y: left.y + bob))
            ear.addLine(to: CGPoint(x: right.x, y: right.y + bob))
            ear.closeSubpath()
            context.fill(ear, with: steel(ear.boundingRect))
            context.stroke(ear, with: .color(.black.opacity(0.3)), lineWidth: 1.5)

            var inner = Path()
            let lean: CGFloat = flip ? -6 : 6
            inner.move(to: CGPoint(x: tip.x + lean, y: tip.y + 13 + bob))
            inner.addLine(to: CGPoint(x: left.x + 8, y: left.y - 6 + bob))
            inner.addLine(to: CGPoint(x: right.x - 8, y: right.y - 6 + bob))
            inner.closeSubpath()
            context.fill(inner, with: .color(Color(red: 0.85, green: 0.52, blue: 0.56).opacity(0.75)))
        }

        var helm = Path()
        helm.move(to: CGPoint(x: 56, y: 96 + bob))
        helm.addQuadCurve(to: CGPoint(x: 100, y: 42 + bob), control: CGPoint(x: 56, y: 50 + bob))
        helm.addQuadCurve(to: CGPoint(x: 144, y: 96 + bob), control: CGPoint(x: 144, y: 50 + bob))
        helm.addQuadCurve(to: CGPoint(x: 100, y: 142 + bob), control: CGPoint(x: 142, y: 142 + bob))
        helm.addQuadCurve(to: CGPoint(x: 56, y: 96 + bob), control: CGPoint(x: 58, y: 142 + bob))
        context.fill(helm, with: steel(helm.boundingRect))
        context.stroke(helm, with: .color(.black.opacity(0.32)), lineWidth: 1.8)

        // Nasal bar down the centre, the detail that makes it read as a helm.
        let nasal = Path(roundedRect: CGRect(x: 95, y: 46 + bob, width: 10, height: 52), cornerRadius: 5)
        context.fill(nasal, with: steel(nasal.boundingRect))
        context.stroke(nasal, with: .color(.black.opacity(0.28)), lineWidth: 1.2)

        // Visor slit.
        let visor = Path(roundedRect: CGRect(x: 64, y: 84 + bob, width: 72, height: 19), cornerRadius: 9)
        context.fill(visor, with: .color(Color(white: 0.07)))

        // Eyes, which blink.
        for x in [83.0, 117.0] {
            let height = 11 * eyeOpening
            guard height > 0.6 else { continue }
            let eye = Path(ellipseIn: CGRect(
                x: x - 5.5,
                y: 93.5 - height / 2 + bob,
                width: 11,
                height: height
            ))
            let halo = Path(ellipseIn: CGRect(
                x: x - 10,
                y: 93.5 - height / 2 - 4 + bob,
                width: 20,
                height: height + 8
            ))
            context.fill(halo, with: .color(Color(red: 0.95, green: 0.78, blue: 0.30).opacity(0.22)))
            context.fill(eye, with: .color(Color(red: 0.97, green: 0.85, blue: 0.38)))
        }

        // Breath holes below the slit.
        for x in stride(from: 84.0, through: 116.0, by: 10.5) {
            let hole = Path(ellipseIn: CGRect(x: x, y: 114 + bob, width: 4, height: 4))
            context.fill(hole, with: .color(.black.opacity(0.45)))
        }
    }
}
