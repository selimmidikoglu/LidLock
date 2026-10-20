import CoreGraphics

/// Where each key physically sits on an ANSI keyboard, measured in key widths
/// from the left edge of its row. A paw is wide enough to cover several
/// neighbours at once, so the detector needs to know which keys are neighbours.
///
/// Modifiers are deliberately unmapped: a human holding Command or Control is
/// the clearest possible sign that the keypresses are deliberate.
enum KeyGeometry {
    static func position(of keyCode: Int64) -> CGPoint? { layout[keyCode] }

    /// Roughly the width of a cat's paw, in key widths.
    static let pawRadius: CGFloat = 2.1

    private static let layout: [Int64: CGPoint] = {
        var map: [Int64: CGPoint] = [:]

        func row(_ y: CGFloat, start: CGFloat, _ codes: [Int64]) {
            for (offset, code) in codes.enumerated() {
                map[code] = CGPoint(x: start + CGFloat(offset), y: y)
            }
        }

        // ` 1 2 3 4 5 6 7 8 9 0 - =  ⌫
        row(3, start: 0, [50, 18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24, 51])
        // ⇥ q w e r t y u i o p [ ] \
        row(2, start: 1.5, [12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30, 42])
        map[48] = CGPoint(x: 0.75, y: 2) // tab
        // a s d f g h j k l ; '
        row(1, start: 1.75, [0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39])
        map[36] = CGPoint(x: 13, y: 1) // return
        // z x c v b n m , . /
        row(0, start: 2.25, [6, 7, 8, 9, 11, 45, 46, 43, 47, 44])
        // space
        map[49] = CGPoint(x: 6.25, y: -1)

        return map
    }()
}
