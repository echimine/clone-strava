#if DEBUG
import AVKit
import SwiftUI

// PROTOTYPE — throwaway (see MediaPrototype.swift).
// Le carrousel carte + médias, partagé par la carte d'Activité (fil, onglet Activités) et
// l'en-tête du détail. Trois variantes :
//   A « Strava »            : diapositives à 86 % de la largeur, la suivante dépasse ; vidéo lue
//                             en boucle et muette quand elle est au centre, durée en haut à droite.
//   B « Pleine largeur »    : une diapositive à la fois, points + « 2/6 » ; vidéo en poster avec ▶︎,
//                             rien ne se lance tout seul.
//   C « Couverture + vignettes » : pas de swipe ; la première diapositive en grand, les suivantes
//                             en vignettes dessous (« +3 ») ; un tap ouvre le visionneur.

enum ProtoCarouselVariants {
    static let all = [
        ProtoVariant(key: "A", name: "Strava, aperçu de la suivante"),
        ProtoVariant(key: "B", name: "Pleine largeur, points"),
        ProtoVariant(key: "C", name: "Couverture + vignettes"),
    ]
}

struct ProtoCarousel: View {
    let activity: ProtoActivity
    let variant: String
    let height: CGFloat
    /// Pleine largeur de l'écran (détail) ou dans la carte arrondie (fil).
    var insetsSlides = true
    let onTapMedia: (ProtoMedia) -> Void
    let onTapMap: () -> Void

    var body: some View {
        let slides = activity.slides
        if slides.isEmpty {
            ProtoSportPlaceholder(sport: activity.sport).frame(height: height * 0.6)
        } else if slides.count == 1 {
            slide(slides[0], isActive: true, autoplay: variant == "A")
                .frame(height: height)
                .clipped()
        } else {
            switch variant {
            case "B": pager(slides)
            case "C": coverAndThumbnails(slides)
            default: peeking(slides)
            }
        }
    }

    // MARK: A

    @State private var currentID: String?

    private func peeking(_ slides: [ProtoSlide]) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 4) {
                ForEach(slides) { item in
                    slide(item, isActive: (currentID ?? slides.first?.id) == item.id, autoplay: true)
                        .frame(height: height)
                        .containerRelativeFrame(.horizontal) { width, _ in width * 0.86 }
                        .clipShape(.rect(cornerRadius: insetsSlides ? 4 : 0))
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $currentID)
        .frame(height: height)
    }

    // MARK: B

    @State private var page = 0

    private func pager(_ slides: [ProtoSlide]) -> some View {
        TabView(selection: $page) {
            ForEach(Array(slides.enumerated()), id: \.element.id) { index, item in
                slide(item, isActive: page == index, autoplay: false).tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: height)
        .overlay(alignment: .topTrailing) {
            Text("\(page + 1)/\(slides.count)")
                .font(.caption.weight(.semibold)).monospacedDigit()
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.black.opacity(0.55), in: Capsule())
                .foregroundStyle(.white)
                .padding(8)
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 5) {
                ForEach(slides.indices, id: \.self) { index in
                    Circle()
                        .fill(index == page ? Color.white : Color.white.opacity(0.5))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(6)
            .background(.black.opacity(0.3), in: Capsule())
            .padding(8)
        }
    }

    // MARK: C

    private func coverAndThumbnails(_ slides: [ProtoSlide]) -> some View {
        let rest = Array(slides.dropFirst())
        let shown = Array(rest.prefix(4))
        return VStack(spacing: 3) {
            slide(slides[0], isActive: true, autoplay: false)
                .frame(height: height * 0.72)
                .clipped()
            HStack(spacing: 3) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                    slide(item, isActive: false, autoplay: false, compact: true)
                        .frame(maxWidth: .infinity)
                        .frame(height: height * 0.28 - 3)
                        .clipped()
                        .overlay {
                            if index == shown.count - 1, rest.count > shown.count {
                                ZStack {
                                    Color.black.opacity(0.5)
                                    Text("+\(rest.count - shown.count)").font(.title2.weight(.bold)).foregroundStyle(.white)
                                }
                                .allowsHitTesting(false)
                            }
                        }
                }
            }
        }
    }

    // MARK: Diapositive

    @ViewBuilder
    private func slide(_ item: ProtoSlide, isActive: Bool, autoplay: Bool, compact: Bool = false) -> some View {
        switch item {
        case .map:
            ProtoMapSlide(route: activity.route, sport: activity.sport)
                .contentShape(.rect)
                .onTapGesture(perform: onTapMap)
        case .media(let media):
            ProtoMediaSlide(media: media, plays: autoplay && isActive, compact: compact)
                .contentShape(.rect)
                .onTapGesture { onTapMedia(media) }
        }
    }
}

// MARK: - Pièces partagées

struct ProtoMapSlide: View {
    let route: EncodedPolyline?
    let sport: SportType
    @Environment(\.mapboxAccessToken) private var token

    var body: some View {
        Color.clear.overlay {
            GeometryReader { proxy in
                RemoteImage(url: route.flatMap { StaticMapURL.make(route: $0, size: proxy.size, accessToken: token) }) {
                    ProtoSportPlaceholder(sport: sport)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .clipped()
    }
}

struct ProtoSportPlaceholder: View {
    let sport: SportType

    var body: some View {
        ZStack {
            Color(.tertiarySystemFill)
            Image(systemName: ActivityFormatters.sportSymbol(sport)).font(.largeTitle).foregroundStyle(.tertiary)
        }
    }
}

/// Une photo, ou une vidéo : son poster, sa durée en haut à droite et, si `plays`, la vidéo
/// muette en boucle par-dessus avec le bouton son en bas à droite.
struct ProtoMediaSlide: View {
    let media: ProtoMedia
    var plays = false
    var compact = false
    @State private var muted = true

    var body: some View {
        ProtoMediaImage(media: media)
            .overlay {
                if plays, let url = media.videoURL {
                    ProtoLoopingVideo(url: url, muted: muted)
                }
            }
            .overlay(alignment: .topTrailing) {
                if media.kind == .video, let seconds = media.durationSeconds, !compact {
                    Text(seconds.protoDuration)
                        .font(.caption.weight(.semibold)).monospacedDigit()
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.black.opacity(0.55), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(8)
                }
            }
            .overlay {
                if media.kind == .video, !plays {
                    Image(systemName: "play.fill")
                        .font(compact ? .caption : .title)
                        .foregroundStyle(.white)
                        .padding(compact ? 6 : 14)
                        .background(.black.opacity(0.45), in: Circle())
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if plays {
                    Button { muted.toggle() } label: {
                        Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.footnote)
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(.black.opacity(0.45), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }
            }
    }
}

struct ProtoMediaImage: View {
    let media: ProtoMedia
    var contentMode = ContentMode.fill

    var body: some View {
        Color.clear.overlay {
            if let image = media.localImage {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else if contentMode == .fill {
                RemoteImage(url: media.imageURL) { Color(.tertiarySystemFill) }
            } else {
                AsyncImage(url: media.imageURL) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    ProgressView().tint(.white)
                }
            }
        }
        .clipped()
    }
}

/// Vidéo en boucle (AVPlayerLooper), remplissant son cadre, sans contrôles.
struct ProtoLoopingVideo: UIViewRepresentable {
    let url: URL
    var muted = true

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        let player = AVQueuePlayer()
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        player.isMuted = muted
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        player.play()
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        view.playerLayer.player?.isMuted = muted
    }

    static func dismantleUIView(_ view: PlayerView, coordinator: Coordinator) {
        view.playerLayer.player?.pause()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator { var looper: AVPlayerLooper? }

    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer } // swiftlint:disable:this force_cast
    }
}
#endif
