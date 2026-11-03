import SwiftUI

/// A row of a followers or following list, a follow request or a search result (ADR-036 §1,
/// §2): avatar and name, which open the athlete's profile, then the row's buttons.
struct AthleteRow<Trailing: View>: View {
    let athlete: ActivityAuthor
    /// The name as shown: a search bolds its matched part.
    var name: AttributedString?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            AthleteButton(athlete: athlete) {
                HStack(spacing: 12) {
                    AvatarView(name: athlete.displayName, url: athlete.avatarURL, size: 44)
                    Text(name ?? AttributedString(athlete.displayName))
                        .font(.body)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            trailing()
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("athleteRow")
    }
}

#Preview {
    List {
        AthleteRow(athlete: ActivityAuthor(id: "lea", displayName: "Léa Bernard", avatarURL: nil)) {
            FollowButton(status: .none, controlSize: .small, onFollow: {}, onUnfollow: {})
        }
        AthleteRow(
            athlete: ActivityAuthor(id: "eli", displayName: "Éliott Martin", avatarURL: nil),
            name: SearchHighlight.highlighted("Éliott Martin", query: "eli")
        ) {
            FollowButton(status: .accepted, controlSize: .small, onFollow: {}, onUnfollow: {})
        }
    }
    .listStyle(.plain)
}
