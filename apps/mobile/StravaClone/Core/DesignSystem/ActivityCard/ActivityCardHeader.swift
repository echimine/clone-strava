import SwiftUI

/// Author, date, sport and place of an activity. The author's avatar and name open their
/// profile (ADR-036 §5, §9).
struct ActivityCardHeader: View {
    let post: ActivityPost
    var now: Date = .now

    var body: some View {
        HStack(spacing: 12) {
            AthleteButton(athlete: post.author) {
                AvatarView(name: post.author.displayName, url: post.author.avatarURL)
            }
            // The name below opens the same profile.
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                AthleteButton(athlete: post.author) {
                    Text(post.author.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                .accessibilityIdentifier("activityCard.author")
                VStack(alignment: .leading, spacing: 2) {
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
                .accessibilityElement(children: .combine)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
    }

    private var subtitle: String {
        let sport = ActivityFormatters.sportLabel(post.sport)
        guard let location = post.locationName else { return sport }
        return "\(sport) · \(location)"
    }
}
