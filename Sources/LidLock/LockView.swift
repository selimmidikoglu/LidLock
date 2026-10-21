import SwiftUI

/// Why the screen is locked. The two reasons want different things on screen
/// and different ways out.
enum LockReason {
    case cleaning
    case cat
}

/// Shared, main-thread-only state driving the lock overlay.
final class LockState: ObservableObject {
    @Published var reason: LockReason = .cleaning
    @Published var digitsEntered: Int = 0
    @Published var wordProgress: Int = 0
    @Published var blockedKeys: Int = 0
    @Published var blockedGestures: Int = 0
    @Published var secondsRemaining: Int? = nil
    @Published var chromeVisible: Bool = true
    @Published var startedAt: Date = Date()
    @Published var showsKitten: Bool = false
}

struct LockView: View {
    @ObservedObject var state: LockState

    var body: some View {
        ZStack {
            Color.black
            Group {
                switch state.reason {
                case .cleaning: cleaningPanel
                case .cat: catPanel
                }
            }
            .opacity(state.chromeVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.7), value: state.chromeVisible)
        }
        .ignoresSafeArea()
    }

    // MARK: - Cleaning

    private var cleaningPanel: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "lock.laptopcomputer")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 74, height: 74)
                .background(Circle().fill(.white.opacity(0.07)))
                .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1))

            Text("Locked for cleaning")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.top, 22)

            Text("Keyboard, trackpad and mouse are disabled.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.top, 6)

            dots
                .padding(.top, 30)

            Text("Type your PIN — a dot appears for each character that matches")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.35))
                .padding(.top, 16)

            Spacer()

            footer
                .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// One dot per matched digit — nothing is drawn until the typed tail starts
    /// matching, so the lock screen never gives away how long the PIN is.
    private var dots: some View {
        HStack(spacing: 11) {
            ForEach(Array(0..<state.digitsEntered), id: \.self) { _ in
                Circle()
                    .fill(.white.opacity(0.85))
                    .frame(width: 9, height: 9)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(height: 9)
        .animation(.easeOut(duration: 0.14), value: state.digitsEntered)
    }

    // MARK: - Cat

    private var catPanel: some View {
        VStack(spacing: 0) {
            Spacer()

            // Only drives frames while the panel is actually on screen — once
            // it fades out there is nothing to animate.
            Group {
                if state.chromeVisible {
                    TimelineView(.animation) { timeline in
                        portrait(at: timeline.date.timeIntervalSince(state.startedAt))
                    }
                } else {
                    portrait(at: 0)
                }
            }
            .frame(
                width: state.showsKitten ? 212 : 190,
                height: state.showsKitten ? 366 : 190
            )

            Text("Cat-like typing detected")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.top, 14)

            Text("The keyboard is held until a human takes over.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.top, 6)

            word
                .padding(.top, 28)

            Text("Type the word to continue")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.35))
                .padding(.top, 14)

            Spacer()

            footer
                .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func portrait(at time: TimeInterval) -> some View {
        if state.showsKitten {
            CatFilmView(time: time)
        } else {
            CatKnight(time: time)
        }
    }

    /// The letters of the unlock word, lighting up the same way the PIN dots do.
    private var word: some View {
        let letters = Array(Preferences.humanWord.uppercased())
        return HStack(spacing: 10) {
            ForEach(letters.indices, id: \.self) { index in
                let lit = index < state.wordProgress
                Text(String(letters[index]))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(lit ? Color(red: 0.97, green: 0.85, blue: 0.38) : .white.opacity(0.22))
                    .frame(width: 32, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(lit ? 0.09 : 0.03))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                lit ? Color(red: 0.97, green: 0.85, blue: 0.38).opacity(0.45) : .white.opacity(0.12),
                                lineWidth: 1
                            )
                    )
            }
        }
        .animation(.easeOut(duration: 0.14), value: state.wordProgress)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            ForEach(Array(footerParts.enumerated()), id: \.offset) { index, part in
                if index > 0 { Text("·") }
                Text(part)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.white.opacity(0.28))
    }

    private var footerParts: [String] {
        var parts: [String] = []
        if let seconds = state.secondsRemaining {
            parts.append("Unlocks automatically in \(Self.clock(seconds))")
        }
        if state.blockedKeys > 0 {
            parts.append("\(state.blockedKeys) \(state.blockedKeys == 1 ? "keystroke" : "keystrokes") blocked")
        }
        if state.blockedGestures > 0 {
            let noun = state.blockedGestures == 1 ? "touch" : "touches"
            parts.append("\(state.blockedGestures) trackpad \(noun) blocked")
        }
        return parts
    }

    private static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
