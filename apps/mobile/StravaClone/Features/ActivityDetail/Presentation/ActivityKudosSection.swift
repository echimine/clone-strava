import SwiftUI

/// Kudos and comments block of the detail, under the stats (ADR-034 §1, ADR-036 §8): the count
/// and the row of the most recent givers (a tap opens the Kudos and comments screen on Kudos),
/// the comment button with its count (that screen on Commentaires, composer focused), and the
/// kudos button, hidden on the viewer's own Activity.
struct ActivityKudosSection: View {
    let store: ActivityDetailStore
    let engagement: ActivityEngagement

    private let avatarSize: CGFloat = 32

    var body: some View {
        HStack(spacing: Theme.spacing) {
            NavigationLink(value: ActivityEngagementRequest.kudos(store.id)) {
                HStack(spacing: 12) {
                    if !store.recentKudos.isEmpty {
                        avatarRow
                    }
                    Text(ActivityDetailMessages.kudosCount(engagement.kudosCount))
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(engagement.kudosCount == 0)
            .accessibilityLabel(ActivityDetailMessages.kudosCount(engagement.kudosCount))
            .accessibilityHint(engagement.kudosCount == 0 ? "" : "Afficher qui a donné un kudos")
            .accessibilityIdentifier("activityDetail.kudosList")

            Spacer(minLength: 0)

            commentsButton

            if store.showsKudosButton {
                kudosButton
            }
        }
        .padding(.horizontal, Theme.spacing)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }

    /// At most 5 overlapping avatars, the most recent first (on top).
    private var avatarRow: some View {
        HStack(spacing: -avatarSize / 4) {
            ForEach(Array(store.recentKudos.enumerated()), id: \.element.id) { index, giver in
                AvatarView(name: giver.athlete.displayName, url: giver.athlete.avatarURL, size: avatarSize)
                    .overlay(Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2))
                    .zIndex(Double(store.recentKudos.count - index))
            }
        }
        .accessibilityIdentifier("activityDetail.kudosAvatars")
    }

    private var commentsButton: some View {
        NavigationLink(value: ActivityEngagementRequest.comments(store.id)) {
            HStack(spacing: 4) {
                Image(systemName: "bubble.right")
                    .font(.title3)
                if engagement.commentCount > 0 {
                    Text(engagement.commentCount.formatted())
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(.primary)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ActivityEngagementMessages.commentsButton(engagement.commentCount))
        .accessibilityIdentifier("activityDetail.comments")
    }

    private var kudosButton: some View {
        Button {
            Task { await store.toggleKudos() }
        } label: {
            Image(systemName: engagement.viewerHasKudoed ? "hand.thumbsup.fill" : "hand.thumbsup")
                .font(.title3)
                .foregroundStyle(engagement.viewerHasKudoed ? Theme.accent : .primary)
                .contentTransition(.symbolEffect(.replace))
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: engagement.viewerHasKudoed)
        .accessibilityLabel(engagement.viewerHasKudoed ? "Retirer le kudos" : "Donner un kudos")
        .accessibilityIdentifier("activityDetail.kudos")
    }
}
