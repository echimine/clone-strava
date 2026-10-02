import SwiftUI

/// One activity in a feed or on a profile (ADR-029): author, date, sport and place, title,
/// stats, route map, then kudos / comments / share.
struct ActivityCard: View {
    let post: ActivityPost
    var onToggleKudos: () -> Void = {}
    var onComments: () -> Void = {}

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

            ActivityMapImage(route: post.route, sport: post.sport)

            ActivitySocialBar(post: post, onToggleKudos: onToggleKudos, onComments: onComments)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
        }
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        .clipShape(.rect(cornerRadius: 20))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activityCard")
    }
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
        route: EncodedPolyline(value: "_p~iF~ps|U_ulLnnqC_mqNvxq`@"),
        author: ActivityAuthor(id: "1", displayName: "Camille Martin", avatarURL: nil),
        engagement: ActivityEngagement(kudosCount: 3, commentCount: 1, viewerHasKudoed: false),
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
