import SwiftUI

/// One activity in a feed or on a profile (ADR-029, ADR-036 §5): author, date, sport and
/// place, title, stats by sport, the carousel of the route map and the Media (ADR-037 §10),
/// then kudos avatars and counts, and kudos / comments / share.
struct ActivityCard: View {
    let post: ActivityPost
    var onToggleKudos: () -> Void = {}
    var onComments: () -> Void = {}
    /// A tap on a Media (the viewer). Without it, the tap opens the detail like the rest of
    /// the card.
    var onTapMedia: ((ActivityMedia) -> Void)?

    /// The author's Media still being sent, merged into the carousel (ADR-037 §5).
    @Environment(\.mediaUploads) private var uploads

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                ActivityCardHeader(post: post)
                Text(post.title)
                    .font(.title3.weight(.bold))
                    .lineLimit(2)
                ActivityStatsRow(post: post)
                    .padding(.horizontal, -8)
            }
            .padding([.horizontal, .top], Theme.spacing)

            carousel

            ActivitySocialBar(post: post, onToggleKudos: onToggleKudos, onComments: onComments)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
        }
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        .clipShape(.rect(cornerRadius: 20))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activityCard")
    }

    /// The map and the Media; the sport icon when there is neither (ADR-037 §10). The map slide
    /// has no tap of its own: it opens the detail like the rest of the card.
    @ViewBuilder private var carousel: some View {
        let slides = post.slides(merging: uploads)
        if slides.isEmpty {
            ActivityMapImage(route: nil, sport: post.sport)
        } else {
            ActivityCarousel(slides: slides, height: Self.carouselHeight, slideCornerRadius: 4, onTapMedia: onTapMedia) {
                ActivityMapImage(
                    route: post.route,
                    sport: post.sport,
                    routeTrimmed: post.routeTrimmed,
                    height: Self.carouselHeight
                )
            }
        }
    }

    private static let carouselHeight: CGFloat = 250
}

extension ActivityPost {
    /// Sample used by previews.
    static let preview = ActivityPost(
        id: ActivityID(),
        title: "Sortie du matin",
        sport: .run,
        startedAt: .now.addingTimeInterval(-3 * 3_600),
        locationName: "Annecy, Haute-Savoie",
        distance: Distance(meters: 10_234),
        movingTime: .seconds(3_130),
        elevationGain: 245,
        avgSpeedMs: 3.27,
        route: EncodedPolyline(value: "_p~iF~ps|U_ulLnnqC_mqNvxq`@"),
        routeTrimmed: true,
        author: ActivityAuthor(id: "1", displayName: "Camille Martin", avatarURL: nil),
        engagement: ActivityEngagement(kudosCount: 3, commentCount: 1, viewerHasKudoed: false),
        recentKudos: [
            ActivityAuthor(id: "2", displayName: "Léa Bernard", avatarURL: nil),
            ActivityAuthor(id: "3", displayName: "Hugo Petit", avatarURL: nil),
            ActivityAuthor(id: "4", displayName: "Inès Moreau", avatarURL: nil),
        ],
        viewerIsAuthor: false
    )
}

#Preview {
    ScrollView {
        ActivityCard(post: .preview)
            .padding()
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Carte et médias") {
    var post = ActivityPost.preview
    post.media = [
        ActivityMedia(
            id: UUID(), kind: .photo, width: 1_200, height: 900, duration: nil,
            url: URL(string: "https://picsum.photos/id/1018/1200/900")!, posterURL: nil,
            thumbURL: URL(string: "https://picsum.photos/id/1018/512/384")!
        ),
        ActivityMedia(
            id: UUID(), kind: .video, width: 1_280, height: 720, duration: .seconds(10),
            url: URL(string: "https://test-videos.co.uk/vids/jellyfish/mp4/h264/720/Jellyfish_720_10s_1MB.mp4")!,
            posterURL: URL(string: "https://picsum.photos/id/1015/1280/720")!,
            thumbURL: URL(string: "https://picsum.photos/id/1015/512/288")!
        ),
    ]
    post.mediaFirst = true
    return ScrollView {
        ActivityCard(post: post, onTapMedia: { _ in })
            .padding()
    }
    .background(Color(.systemGroupedBackground))
}
