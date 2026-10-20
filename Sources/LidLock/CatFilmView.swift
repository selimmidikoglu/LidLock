import SwiftUI

/// The kitten knight himself, when his frames are installed.
struct CatFilmView: View {
    let time: TimeInterval

    var body: some View {
        let frames = CatFilm.frames
        Group {
            if frames.isEmpty {
                Color.clear
            } else {
                Image(nsImage: frames[min(CatFilm.index(at: time), frames.count - 1)])
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            }
        }
        // The clip was shot against a bright sky. Left as a hard rectangle it
        // would read as a sticker pasted onto the lock screen, so the top melts
        // into the black while the armour at the bottom stays crisp.
        .mask(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white, location: 0.18),
                            .init(color: .white, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
    }
}
