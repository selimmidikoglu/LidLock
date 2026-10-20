import CoreGraphics
import Foundation

/// Decides whether the keyboard is being walked on rather than typed on.
///
/// It reads nothing but key positions and timing — never which characters the
/// keys produce — and looks for two things a hand does not do:
///
/// * a **paw**: three or more neighbouring keys pressed together and held
///   longer than the roll-over of fast typing, and
/// * a **lie-down**: three or more keys, anywhere on the board, pinned for
///   longer than a second and a half, which is a cat settling its weight.
///
/// Holding a single key for a long time is deliberately *not* evidence: people
/// lean on backspace and arrow keys all day.
///
/// One narrow paw is suggestive rather than conclusive, so evidence is scored
/// and the detector fires once enough of it lands inside a short window. All
/// methods must be called on the main thread.
final class PawDetector {
    struct Sensitivity {
        /// Evidence needed before the detector fires.
        let scoreToTrigger: Int
        /// How long neighbouring keys must overlap to count as a paw.
        let clusterHold: TimeInterval

        /// Fires on a single narrow paw.
        static let eager = Sensitivity(scoreToTrigger: 1, clusterHold: 0.08)
        /// Two paw steps, or one wide paw, or a lie-down.
        static let balanced = Sensitivity(scoreToTrigger: 2, clusterHold: 0.12)
        /// Waits for a cat that is clearly committed to the keyboard.
        static let relaxed = Sensitivity(scoreToTrigger: 3, clusterHold: 0.16)
    }

    /// Fired once the evidence adds up. The detector resets itself first, so the
    /// callback is free to lock.
    var onPaw: (() -> Void)?

    private var sensitivity: Sensitivity
    /// Evidence stays relevant only this long — a cat crosses in a few seconds.
    private let window: TimeInterval = 4
    private let lieDownHold: TimeInterval = 1.5
    private let minimumKeys = 3

    private var held: [Int64: TimeInterval] = [:]
    private var scored: [(at: TimeInterval, points: Int)] = []
    /// Keys whose paw has already been counted, so one sustained press scores
    /// once rather than once per poll.
    private var countedPaw: Set<Int64> = []
    private var countedLieDown: Set<Int64> = []
    private var poll: Timer?

    init(sensitivity: Sensitivity = .balanced) {
        self.sensitivity = sensitivity
    }

    func update(sensitivity: Sensitivity) {
        self.sensitivity = sensitivity
        reset()
    }

    func reset() {
        held.removeAll()
        scored.removeAll()
        countedPaw.removeAll()
        countedLieDown.removeAll()
        poll?.invalidate()
        poll = nil
    }

    // MARK: - Input

    /// Someone reaching for a shortcut is not a cat. Any modifier wipes the slate.
    func modifiersChanged(active: Bool) {
        if active { reset() }
    }

    func keyDown(_ keyCode: Int64, at time: TimeInterval) {
        guard KeyGeometry.position(of: keyCode) != nil else { return }
        if held[keyCode] == nil { held[keyCode] = time }
        startPolling()
    }

    func keyUp(_ keyCode: Int64) {
        held.removeValue(forKey: keyCode)
        countedPaw.remove(keyCode)
        countedLieDown.remove(keyCode)
        if held.isEmpty {
            poll?.invalidate()
            poll = nil
        }
    }

    // MARK: - Evidence

    /// Both signals are about how long keys stay down, so neither can be judged
    /// the moment a key lands — the detector watches the held set instead.
    private func startPolling() {
        guard poll == nil else { return }
        poll = Timer.scheduledTimer(withTimeInterval: sensitivity.clusterHold, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            guard !self.held.isEmpty else {
                timer.invalidate()
                self.poll = nil
                return
            }
            self.examineHeldKeys()
        }
    }

    private func examineHeldKeys() {
        let now = ProcessInfo.processInfo.systemUptime

        let settled = held.filter { now - $0.value >= sensitivity.clusterHold }
        guard settled.count >= minimumKeys else { return }

        let lingering = held.filter { now - $0.value >= lieDownHold }
        if lingering.count >= minimumKeys, !lingering.keys.allSatisfy(countedLieDown.contains) {
            lingering.keys.forEach { countedLieDown.insert($0) }
            award(2, at: now)
            return
        }

        let placed = settled.keys.compactMap { code -> (Int64, CGPoint)? in
            KeyGeometry.position(of: code).map { (code, $0) }
        }

        for (_, origin) in placed {
            let paw = placed.filter { hypot($0.1.x - origin.x, $0.1.y - origin.y) <= KeyGeometry.pawRadius }
            guard paw.count >= minimumKeys else { continue }
            guard !paw.allSatisfy({ countedPaw.contains($0.0) }) else { continue }
            paw.forEach { countedPaw.insert($0.0) }
            // The wider the paw, the less room there is for doubt.
            award(min(paw.count - 2, 3), at: now)
            return
        }
    }

    private func award(_ points: Int, at time: TimeInterval) {
        scored.append((at: time, points: points))
        scored.removeAll { time - $0.at > window }
        guard scored.reduce(0, { $0 + $1.points }) >= sensitivity.scoreToTrigger else { return }
        reset()
        onPaw?()
    }
}
