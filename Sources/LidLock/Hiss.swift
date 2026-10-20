import AVFoundation

/// A short burst of filtered noise — the sound a cat reads as "get off".
/// Synthesised rather than shipped as an asset so the app stays a single binary
/// with no bundled media.
enum Hiss {
    private static let engine = AVAudioEngine()
    private static let player = AVAudioPlayerNode()
    private static var buffer: AVAudioPCMBuffer?
    private static var prepared = false

    static func play() {
        guard prepare(), let buffer else { return }
        if !player.isPlaying { player.play() }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
    }

    static func stop() {
        guard prepared else { return }
        player.stop()
    }

    private static func prepare() -> Bool {
        if prepared { return true }

        let sampleRate = 44_100.0
        let duration = 0.45
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let scratch = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(sampleRate * duration)
              ) else { return false }

        let frames = Int(sampleRate * duration)
        scratch.frameLength = AVAudioFrameCount(frames)
        guard let samples = scratch.floatChannelData?[0] else { return false }

        // White noise, steered towards the high end a cat reacts to by
        // subtracting the previous sample, then shaped so it fades rather than
        // clicking off.
        var previous: Float = 0
        for index in 0..<frames {
            let white = Float.random(in: -1...1)
            let bright = white - previous * 0.85
            previous = white

            let progress = Float(index) / Float(frames)
            let attack = min(progress / 0.04, 1)
            let release = min((1 - progress) / 0.5, 1)
            samples[index] = bright * attack * release * 0.22
        }

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
        } catch {
            return false
        }

        buffer = scratch
        prepared = true
        return true
    }
}
