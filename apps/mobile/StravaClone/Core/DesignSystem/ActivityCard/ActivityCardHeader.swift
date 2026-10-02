import SwiftUI

/// Author, date, sport and place of an activity.
struct ActivityCardHeader: View {
    let post: ActivityPost
    var now: Date = .now

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(name: post.author.displayName, url: post.author.avatarURL)
            VStack(alignment: .leading, spacing: 2) {
                Text(post.author.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(ActivityFormatters.relativeDateTime(post.startedAt, now: now))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Image(systemName: ActivityFormatters.sportSymbol(post.sport))
                    Text(subtitle).lineLimit(1)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let sport = ActivityFormatters.sportLabel(post.sport)
        guard let location = post.locationName else { return sport }
        return "\(sport) · \(location)"
    }
}
