import AppKit
import SwiftUI

/// Renders the app's own lock screens to a frame sequence, which `make-demo.sh`
/// turns into the demo in the README. The views are the real ones, compiled
/// from `Sources/LidLock` — nothing here is a mock-up.
@main
struct Demo {
    static let fps = 8.0
    static let size = CGSize(width: 840, height: 660)
    static let total = 30.0

    @MainActor
    static func main() {
        let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
        CatFilm.load()
        if CatFilm.frames.isEmpty {
            FileHandle.standardError.write(Data("no kitten frames next to the binary\n".utf8))
        }

        var frame = 0
        var t = 0.0
        while t < total {
            write(cat(at: t), to: dir, frame: &frame)
            t += 1 / fps
        }
        print("\(frame) frames → \(dir)")
    }

    /// The cat lock: the kitten plays, the unlock word fills in letter by letter.
    @MainActor
    private static func cat(at t: Double) -> LockState {
        let state = LockState()
        state.reason = .cat
        state.showsKitten = !CatFilm.frames.isEmpty
        state.wordProgress = min(5, max(0, Int((t - 13.0) / 1.6) + 1))
        state.blockedKeys = 14 + Int(t * 4)
        state.secondsRemaining = 300 - Int(t)
        // Both portraits read the clock through `startedAt`, so winding that
        // back is what moves the animation on.
        state.startedAt = Date().addingTimeInterval(-t)
        return state
    }

    @MainActor
    private static func write(_ state: LockState, to dir: String, frame: inout Int) {
        let renderer = ImageRenderer(
            content: LockView(state: state).frame(width: size.width, height: size.height)
        )
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("frame \(frame) failed\n".utf8))
            exit(1)
        }
        try? png.write(to: URL(fileURLWithPath: String(format: "%@/f_%04d.png", dir, frame)))
        frame += 1
    }
}
