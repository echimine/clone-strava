import SwiftUI

/// The card's social row (ADR-036 §5): up to 3 kudos avatars and "N ont envoyé des kudos ·
/// N commentaires", then the kudos 👍, comments 💬 and share actions.
struct ActivitySocialBar: View {
    let post: ActivityPost
    let onToggleKudos: () -> Void
    let onComments: () -> Void
    /// My own Activity: no kudos to myself, the 👍 opens who gave kudos (like Strava).
    var onShowKudos: () -> Void = {}

    private var summary: String? {
        ActivityCardMessages.socialSummary(
            kudosCount: post.engagement.kudosCount,
            commentCount: post.engagement.commentCount
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let summary {
                HStack(spacing: 8) {
                    if !post.recentKudos.isEmpty {
                        KudosAvatarStack(givers: Array(post.recentKudos.prefix(3)))
                    }
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("activityCard.socialSummary")
            }
            buttons
        }
    }

    private var buttons: some View {
        HStack(spacing: 0) {
            Button(action: post.viewerIsAuthor ? onShowKudos : onToggleKudos) {
                Image(systemName: post.engagement.viewerHasKudoed ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .foregroundStyle(post.engagement.viewerHasKudoed ? Theme.accent : .primary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(.rect)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: post.engagement.viewerHasKudoed)
            .accessibilityLabel(kudosLabel)
            .accessibilityValue("\(post.engagement.kudosCount) kudos")
            .accessibilityIdentifier("activityCard.kudos")

            Button(action: onComments) {
                Image(systemName: "bubble.left")
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Commentaires")
            .accessibilityValue("\(post.engagement.commentCount)")
            .accessibilityIdentifier("activityCard.comments")

            ShareLink(item: ActivityFormatters.shareText(for: post)) {
                Image(systemName: "square.and.arrow.up")
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Partager")
            .accessibilityIdentifier("activityCard.share")
        }
        .buttonStyle(.plain)
        .font(.body.weight(.medium))
    }

    private var kudosLabel: String {
        if post.viewerIsAuthor { return "Voir les kudos" }
        return post.engagement.viewerHasKudoed ? "Retirer le kudos" : "Donner un kudos"
    }
}
