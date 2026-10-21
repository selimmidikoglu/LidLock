import AVFoundation

/// The two noises the app makes, both synthesised rather than shipped as audio
/// files — a recording would need a licence, and these are a few lines of maths.
enum Sounds {
    private static let engine = AVAudioEngine()
    private static let player = AVAudioPlayerNode()
    private static var started = false
    private static let sampleRate = 44_100.0

    /// Starts the engine on first use. A menu bar app that may never lock the
    /// screen has no business holding an audio graph open from launch.
    /// `interrupting: false` queues the buffer behind whatever is already
    /// scheduled, which is how the hiss comes out after the meow rather than
    /// cutting it in half.
    private static func play(_ buffer: AVAudioPCMBuffer?, interrupting: Bool = true) {
        guard let buffer else { return }
        if !started {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
            guard (try? engine.start()) != nil else { return }
            started = true
        }
        if !player.isPlaying { player.play() }
        player.scheduleBuffer(buffer, at: nil, options: interrupting ? .interrupts : [])
    }

    /// What a cat hears when it is caught: a meow, then the hiss behind it.
    static func catAlarm() {
        play(Meow.sound)
        play(Hiss.sound, interrupting: false)
    }

    static func stop() {
        guard started else { return }
        player.stop()
    }

    /// Fills a buffer from a closure, then scales the whole thing to `peak`.
    /// Synthesis gains are guesswork — a resonator can multiply its input
    /// several times over — so the level is settled afterwards, by measurement.
    private static func buffer(seconds: Double, peak: Float,
                               _ sample: (_ time: Double, _ progress: Double) -> Float)
    -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(sampleRate * seconds)
              ), let samples = buffer.floatChannelData?[0] else { return nil }

        let frames = Int(sampleRate * seconds)
        buffer.frameLength = AVAudioFrameCount(frames)
        var loudest: Float = 0
        for index in 0..<frames {
            let value = sample(Double(index) / sampleRate, Double(index) / Double(frames))
            samples[index] = value
            loudest = max(loudest, abs(value))
        }
        guard loudest > 0 else { return buffer }
        let scale = peak / loudest
        for index in 0..<frames { samples[index] *= scale }
        return buffer
    }

    /// A two-pole resonator, which is all a vowel really is: a peak in the
    /// spectrum. Two of them stacked turn a buzz into a voice.
    private struct Formant {
        private var previous: Float = 0
        private var earlier: Float = 0

        mutating func callAsFunction(_ input: Float, frequency: Double, bandwidth: Double,
                                     sampleRate: Double) -> Float {
            let r = exp(-Double.pi * bandwidth / sampleRate)
            let theta = 2 * Double.pi * frequency / sampleRate
            let b1 = Float(2 * r * cos(theta))
            let b2 = Float(-r * r)
            let gain = Float(1 - r * r)
            let output = gain * input + b1 * previous + b2 * earlier
            earlier = previous
            previous = output
            return output
        }
    }

    private static func ramp(_ progress: Double, _ points: [(Double, Double)]) -> Double {
        for index in 1..<points.count where progress <= points[index].0 {
            let (p0, v0) = points[index - 1]
            let (p1, v1) = points[index]
            let t = p1 == p0 ? 0 : (progress - p0) / (p1 - p0)
            return v0 + (v1 - v0) * t
        }
        return points.last?.1 ?? 0
    }

    // MARK: - Voices

    /// A burst of noise steered high, where a cat's attention lives.
    enum Hiss {
        static let sound: AVAudioPCMBuffer? = {
            var previous: Float = 0
            return Sounds.buffer(seconds: 0.45, peak: 0.40) { _, progress in
                let white = Float.random(in: -1...1)
                let bright = white - previous * 0.85
                previous = white
                let attack = Float(min(progress / 0.04, 1))
                let release = Float(min((1 - progress) / 0.5, 1))
                return bright * attack * release * 0.22
            }
        }()

        static func stop() { Sounds.stop() }
    }

    /// A recorded cat, with a synthesised stand-in — the arching buzz of a
    /// cord through two resonators — for a bundle that has lost the recording.
    enum Meow {
        static let sound: AVAudioPCMBuffer? = recorded() ?? synthesised

        /// Reads `Sounds/meow.m4a` from the bundle. The engine is wired for one
        /// format, so a file in any other is left alone rather than resampled
        /// on the way to a lock screen.
        private static func recorded() -> AVAudioPCMBuffer? {
            guard let url = Bundle.main.resourceURL?
                    .appendingPathComponent("Sounds/meow.m4a"),
                  FileManager.default.fileExists(atPath: url.path),
                  let file = try? AVAudioFile(forReading: url),
                  file.processingFormat.sampleRate == Sounds.sampleRate,
                  file.processingFormat.channelCount == 1,
                  let buffer = AVAudioPCMBuffer(
                      pcmFormat: file.processingFormat,
                      frameCapacity: AVAudioFrameCount(file.length)
                  ),
                  (try? file.read(into: buffer)) != nil
            else { return nil }
            return buffer
        }

        private static let synthesised: AVAudioPCMBuffer? = {
            var phase = 0.0
            var first = Formant()
            var second = Formant()
            return Sounds.buffer(seconds: 0.62, peak: 0.55) { time, progress in
                // The pitch arch, with the small wobble that keeps it alive.
                let pitch = Sounds.ramp(progress, [(0, 520), (0.18, 700), (0.55, 620), (1, 360)])
                    * (1 + 0.025 * sin(2 * .pi * 5.5 * time))
                phase += 2 * .pi * pitch / Sounds.sampleRate
                if phase > 2 * .pi { phase -= 2 * .pi }

                // A sawtooth built from a handful of harmonics: enough edge to
                // filter, none of the aliasing a naive ramp would fold back.
                var cord = 0.0
                for harmonic in 1...12 {
                    cord += sin(phase * Double(harmonic)) / Double(harmonic)
                }

                let open = Sounds.ramp(progress, [(0, 420), (0.3, 900), (0.7, 820), (1, 500)])
                let close = Sounds.ramp(progress, [(0, 2300), (0.3, 1300), (0.7, 1150), (1, 900)])
                var voice = first(Float(cord), frequency: open, bandwidth: 110,
                                  sampleRate: Sounds.sampleRate)
                voice += 0.6 * second(Float(cord), frequency: close, bandwidth: 180,
                                      sampleRate: Sounds.sampleRate)

                let attack = Float(min(progress / 0.07, 1))
                let release = Float(min((1 - progress) / 0.35, 1))
                return voice * attack * release * 0.5
            }
        }()

    }
}
