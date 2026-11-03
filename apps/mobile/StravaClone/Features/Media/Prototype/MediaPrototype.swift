#if DEBUG
import SwiftUI

// PROTOTYPE — throwaway. Ticket « Prototype du carrousel, du visionneur et de la Galerie »
// (#162), carte « Photos, vidéos et avatar sur iOS » (#156). Branche prototype/media-carousel-gallery,
// jamais fusionnée.
//
// Lancement : argument `-MediaPrototype` (Edit Scheme > Run > Arguments), à la place de l'app.
// Quatre onglets : Fil, Détail, Profil (Galerie), Édition. Chacun a ses variantes, cyclées par la
// pastille ‹ › en bas ; « Visionneur » cycle les variantes du plein écran. Les variantes sont aussi
// choisissables au lancement : `-protoFeed B -protoViewer C -protoGallery A -protoEditor B`.
// Tout est en mémoire : photos picsum.photos, vidéos test-videos.co.uk, rien n'est envoyé.

enum MediaPrototype {
    static let launchArgument = "-MediaPrototype"
}

// MARK: - Modèle

struct ProtoMedia: Identifiable, Hashable {
    enum Kind: Hashable { case photo, video }

    let id = UUID()
    let kind: Kind
    /// La photo, ou le poster d'une vidéo.
    var imageURL: URL?
    var videoURL: URL?
    /// Ajoutée depuis la photothèque dans l'onglet Édition.
    var localImage: UIImage?
    var durationSeconds: Int?
    /// Largeur / hauteur de l'original.
    var aspect: CGFloat

    static func photo(_ picsumID: Int, aspect: CGFloat = 4 / 3) -> ProtoMedia {
        let width = 1_200
        let height = Int(CGFloat(width) / aspect)
        return ProtoMedia(kind: .photo, imageURL: URL(string: "https://picsum.photos/id/\(picsumID)/\(width)/\(height)"), aspect: aspect)
    }

    static func video(_ name: ProtoVideo, poster picsumID: Int) -> ProtoMedia {
        ProtoMedia(
            kind: .video,
            imageURL: URL(string: "https://picsum.photos/id/\(picsumID)/1280/720"),
            videoURL: name.url,
            durationSeconds: 10,
            aspect: 16 / 9
        )
    }
}

enum ProtoVideo: String {
    case jellyfish = "jellyfish/mp4/h264/720/Jellyfish_720_10s_1MB.mp4"
    case sintel = "sintel/mp4/h264/720/Sintel_720_10s_1MB.mp4"
    case bunny = "bigbuckbunny/mp4/h264/720/Big_Buck_Bunny_720_10s_1MB.mp4"

    var url: URL? { URL(string: "https://test-videos.co.uk/vids/\(rawValue)") }
}

/// Une diapositive du carrousel : la carte ou un média. L'ordre de `slides` est l'ordre affiché ;
/// « photo en premier à la place de la carte » = un média avant `.map`.
enum ProtoSlide: Identifiable, Hashable {
    case map
    case media(ProtoMedia)

    var id: String {
        switch self {
        case .map: "map"
        case .media(let media): media.id.uuidString
        }
    }

    var media: ProtoMedia? {
        if case .media(let media) = self { media } else { nil }
    }
}

@Observable
final class ProtoActivity: Identifiable {
    let id = ActivityID()
    var title: String
    let sport: SportType
    let startedAt: Date
    let locationName: String
    let distanceKm: Double?
    let minutes: Int
    let elevation: Double?
    let route: EncodedPolyline?
    var slides: [ProtoSlide]
    let author: ActivityAuthor
    var engagement: ActivityEngagement

    init(
        title: String, sport: SportType, daysAgo: Double, place: String, km: Double?, minutes: Int,
        elevation: Double?, route: EncodedPolyline?, media: [ProtoMedia], mapFirst: Bool = true,
        author: ActivityAuthor = .protoMe, kudos: Int = 4, comments: Int = 1
    ) {
        self.title = title
        self.sport = sport
        startedAt = .now.addingTimeInterval(-daysAgo * 86_400)
        locationName = place
        distanceKm = km
        self.minutes = minutes
        self.elevation = elevation
        self.route = route
        let mediaSlides = media.map(ProtoSlide.media)
        if route == nil {
            slides = mediaSlides
        } else if mapFirst || mediaSlides.isEmpty {
            slides = [.map] + mediaSlides
        } else {
            slides = [mediaSlides[0], .map] + mediaSlides.dropFirst()
        }
        self.author = author
        engagement = ActivityEngagement(kudosCount: kudos, commentCount: comments, viewerHasKudoed: false)
    }

    var media: [ProtoMedia] { slides.compactMap(\.media) }
    var hasMap: Bool { slides.contains(.map) }
    var isMine: Bool { author == .protoMe }

    var post: ActivityPost {
        ActivityPost(
            id: id,
            title: title,
            sport: sport,
            startedAt: startedAt,
            locationName: locationName,
            distance: distanceKm.map { Distance(meters: $0 * 1_000) },
            movingTime: .seconds(minutes * 60),
            elevationGain: elevation,
            avgSpeedMs: distanceKm.map { $0 * 1_000 / Double(minutes * 60) },
            route: route,
            routeTrimmed: false,
            author: author,
            engagement: engagement,
            recentKudos: [ActivityAuthor(id: "k1", displayName: "Léa Bernard", avatarURL: nil)],
            viewerIsAuthor: isMine
        )
    }
}

extension ActivityAuthor {
    static let protoMe = ActivityAuthor(
        id: "me", displayName: "Eliott Chiminello", avatarURL: URL(string: "https://picsum.photos/id/64/200/200")
    )
    static let protoCamille = ActivityAuthor(
        id: "camille", displayName: "Camille Martin", avatarURL: URL(string: "https://picsum.photos/id/65/200/200")
    )
}

/// Un média ouvert dans le visionneur, avec son Activité (pour le lien « Voir l'activité »).
struct ProtoViewerItem: Identifiable {
    let media: ProtoMedia
    let activity: ProtoActivity
    var id: UUID { media.id }
}

struct ProtoViewerRequest: Identifiable {
    let id = UUID()
    let items: [ProtoViewerItem]
    let start: Int
    /// Depuis la Galerie : lien vers l'Activité. Depuis une carte : on y est déjà.
    let showsActivityLink: Bool
}

@Observable
final class ProtoStore {
    var activities: [ProtoActivity] = ProtoSamples.activities()
    var viewer: ProtoViewerRequest?
    /// Activité ouverte par « Voir l'activité » depuis le visionneur ou par un tap sur une carte.
    var openedActivity: ProtoActivity?
    /// `-protoTab detail|profile|editor` au lancement pour ouvrir directement un onglet.
    var selectedTab = ProtoTab(rawValue: UserDefaults.standard.string(forKey: "protoTab") ?? "") ?? .feed

    /// Le visionneur sur les médias d'une Activité, ouvert sur `media` (la carte n'y est pas).
    func openViewer(_ activity: ProtoActivity, at media: ProtoMedia) {
        let items = activity.media.map { ProtoViewerItem(media: $0, activity: activity) }
        let start = items.firstIndex { $0.media.id == media.id } ?? 0
        viewer = ProtoViewerRequest(items: items, start: start, showsActivityLink: false)
    }

    /// Tous les médias d'un athlète, du plus récent au plus ancien (Galerie).
    func galleryItems(of author: ActivityAuthor) -> [ProtoViewerItem] {
        activities
            .filter { $0.author == author }
            .sorted { $0.startedAt > $1.startedAt }
            .flatMap { activity in activity.media.map { ProtoViewerItem(media: $0, activity: activity) } }
    }
}

enum ProtoTab: String, Hashable { case feed, detail, profile, editor }

// MARK: - Racine

struct MediaPrototypeView: View {
    @State private var store = ProtoStore()
    @AppStorage("protoViewer") private var viewerVariant = "A"

    var body: some View {
        TabView(selection: $store.selectedTab) {
            ProtoFeedTab(store: store)
                .tabItem { Label("Fil", systemImage: "house") }
                .tag(ProtoTab.feed)
            ProtoDetailTab(store: store)
                .tabItem { Label("Détail", systemImage: "doc.text.image") }
                .tag(ProtoTab.detail)
            ProtoProfileTab(store: store)
                .tabItem { Label("Profil", systemImage: "person") }
                .tag(ProtoTab.profile)
            ProtoEditorTab(store: store)
                .tabItem { Label("Édition", systemImage: "square.and.pencil") }
                .tag(ProtoTab.editor)
        }
        .fullScreenCover(item: $store.viewer) { request in
            ProtoViewer(request: request, variant: $viewerVariant) { activity in
                store.viewer = nil
                store.openedActivity = activity
                store.selectedTab = .detail
            }
        }
    }
}

// MARK: - Pastille de variantes

struct ProtoVariant: Hashable {
    let key: String
    let name: String
}

/// Pastille flottante ‹ variante › : clairement hors du design évalué.
struct ProtoSwitcher: View {
    let title: String
    let variants: [ProtoVariant]
    @Binding var current: String
    var showsViewerToggle = true
    @AppStorage("protoViewer") private var viewerVariant = "A"

    var body: some View {
        HStack(spacing: 4) {
            Button { cycle(-1) } label: { Image(systemName: "chevron.left").frame(width: 32, height: 32) }
            VStack(spacing: 0) {
                Text("\(title) \(current)").font(.caption.weight(.bold))
                Text(variants.first { $0.key == current }?.name ?? "").font(.caption2)
            }
            .frame(minWidth: 120)
            Button { cycle(1) } label: { Image(systemName: "chevron.right").frame(width: 32, height: 32) }
            if showsViewerToggle {
                Divider().frame(height: 24).overlay(.white.opacity(0.4))
                Button {
                    let keys = ProtoViewer.variants.map(\.key)
                    viewerVariant = keys[((keys.firstIndex(of: viewerVariant) ?? 0) + 1) % keys.count]
                } label: {
                    VStack(spacing: 0) {
                        Text("Visionneur \(viewerVariant)").font(.caption.weight(.bold))
                        Text(ProtoViewer.variants.first { $0.key == viewerVariant }?.name ?? "").font(.caption2)
                    }
                    .padding(.horizontal, 6)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.purple.opacity(0.9), in: Capsule())
        .shadow(radius: 6)
        .buttonStyle(.plain)
        .padding(.bottom, 6)
    }

    private func cycle(_ step: Int) {
        let keys = variants.map(\.key)
        let index = keys.firstIndex(of: current) ?? 0
        withAnimation(.snappy) { current = keys[(index + step + keys.count) % keys.count] }
    }
}

// MARK: - Données d'exemple

enum ProtoSamples {
    static func activities() -> [ProtoActivity] {
        [
            ProtoActivity(
                title: "Sortie du matin au bord du lac", sport: .run, daysAgo: 0.2, place: "Annecy, Haute-Savoie",
                km: 10.2, minutes: 52, elevation: 84, route: loop(lat: 45.899, lon: 6.129, radius: 0.012, wobble: 0.25),
                media: [.photo(1018), .video(.jellyfish, poster: 1015), .photo(1039, aspect: 3 / 4), .photo(1043), .video(.sintel, poster: 1036)]
            ),
            ProtoActivity(
                title: "Col de la Forclaz", sport: .ride, daysAgo: 1.3, place: "Talloires-Montmin",
                km: 48.6, minutes: 142, elevation: 1_120, route: loop(lat: 45.81, lon: 6.24, radius: 0.05, wobble: 0.4),
                media: [.photo(1016), .photo(1019), .video(.bunny, poster: 1022), .photo(1029, aspect: 3 / 4),
                        .photo(1035), .photo(1044), .photo(1051), .photo(1056)],
                mapFirst: false, kudos: 18, comments: 5
            ),
            ProtoActivity(
                title: "Fractionné sur tapis", sport: .run, daysAgo: 2.5, place: "Annecy",
                km: 8.0, minutes: 40, elevation: nil, route: nil,
                media: [.photo(1060, aspect: 3 / 4), .video(.sintel, poster: 1062)]
            ),
            ProtoActivity(
                title: "Footing récup", sport: .run, daysAgo: 3.4, place: "Seynod",
                km: 6.1, minutes: 35, elevation: 40, route: loop(lat: 45.885, lon: 6.09, radius: 0.008, wobble: 0.15),
                media: []
            ),
            ProtoActivity(
                title: "Semnoz par la crête", sport: .hike, daysAgo: 5, place: "Semnoz",
                km: 14.3, minutes: 255, elevation: 960, route: loop(lat: 45.80, lon: 6.10, radius: 0.03, wobble: 0.5),
                media: [.photo(1080)]
            ),
            ProtoActivity(
                title: "Tour du Semnoz", sport: .ride, daysAgo: 0.5, place: "Annecy",
                km: 62, minutes: 168, elevation: 1_350, route: loop(lat: 45.83, lon: 6.11, radius: 0.06, wobble: 0.3),
                media: [.photo(1002), .photo(1003), .video(.bunny, poster: 1004)],
                author: .protoCamille, kudos: 9, comments: 2
            ),
        ]
    }

    /// Une boucle ondulée autour d'un point, encodée en polyline Google (précision 5).
    static func loop(lat: Double, lon: Double, radius: Double, wobble: Double) -> EncodedPolyline {
        let points = (0 ... 60).map { step -> (Double, Double) in
            let angle = Double(step) / 60 * 2 * .pi
            let r = radius * (1 + wobble * sin(angle * 3) * 0.5)
            return (lat + r * sin(angle), lon + r * 1.4 * cos(angle))
        }
        var result = ""
        var previous = (0, 0)
        for (latitude, longitude) in points {
            let current = (Int((latitude * 1e5).rounded()), Int((longitude * 1e5).rounded()))
            for delta in [current.0 - previous.0, current.1 - previous.1] {
                var value = delta < 0 ? ~(delta << 1) : delta << 1
                while value >= 0x20 {
                    result.append(Character(UnicodeScalar(UInt8((0x20 | (value & 0x1F)) + 63))))
                    value >>= 5
                }
                result.append(Character(UnicodeScalar(UInt8(value + 63))))
            }
            previous = current
        }
        return EncodedPolyline(value: result)
    }
}

extension Int {
    var protoDuration: String { String(format: "%d:%02d", self / 60, self % 60) }
}
#endif
