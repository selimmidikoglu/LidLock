import AppKit

/// The kitten-knight frames, if they are present in the bundle.
///
/// They are loaded only while a cat lock is on screen and dropped the moment it
/// ends — a menu bar utility has no business holding twenty megabytes of
/// decoded photographs while it sits idle.
///
/// The clip is third-party footage and is deliberately kept out of version
/// control, so a fresh checkout has no frames and falls back to the drawn
/// knight. Everything here copes with the folder simply not existing.
enum CatFilm {
    static let frameRate: Double = 12

    private(set) static var frames: [NSImage] = []

    static var isAvailable: Bool { !frameURLs.isEmpty }

    private static var frameURLs: [URL] {
        guard let folder = Bundle.main.resourceURL?.appendingPathComponent("CatFilm"),
              let contents = try? FileManager.default.contentsOfDirectory(
                  at: folder,
                  includingPropertiesForKeys: nil
              ) else { return [] }
        return contents.filter { $0.pathExtension.lowercased() == "jpg" }.sorted {
            $0.lastPathComponent < $1.lastPathComponent
        }
    }

    static func load() {
        guard frames.isEmpty else { return }
        frames = frameURLs.compactMap { NSImage(contentsOf: $0) }
    }

    static func unload() {
        frames.removeAll()
    }

    /// Plays forward and then back, so a clip with no natural loop still cycles
    /// without a jump. The pull-back of the camera reads as a slow breath.
    static func index(at time: TimeInterval) -> Int {
        let count = frames.count
        guard count > 1 else { return 0 }
        let period = count * 2 - 2
        let step = Int(time * frameRate) % period
        return step < count ? step : period - step
    }
}
