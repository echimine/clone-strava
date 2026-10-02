import SwiftUI

/// Kudos 👍, comments 💬 and share actions of an activity.
struct ActivitySocialBar: View {
    let post: ActivityPost
    let onToggleKudos: () -> Void
    let onComments: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onToggleKudos) {
                Label {
                    Text(post.engagement.kudosCount, format: .number)
                } icon: {
                    Image(systemName: post.engagement.viewerHasKudoed ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .foregroundStyle(post.engagement.viewerHasKudoed ? Theme.accent : .primary)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .disabled(post.viewerIsAuthor)
            .sensoryFeedback(.impact(weight: .light), trigger: post.engagement.viewerHasKudoed)
            .accessibilityLabel(post.engagement.viewerHasKudoed ? "Retirer le kudos" : "Donner un kudos")
            .accessibilityValue("\(post.engagement.kudosCount) kudos")
            .accessibilityIdentifier("activityCard.kudos")
            .frame(maxWidth: .infinity)

            Button(action: onComments) {
                Label {
                    Text(post.engagement.commentCount, format: .number)
                } icon: {
                    Image(systemName: "bubble.left")
                }
            }
            .accessibilityLabel("Commentaires")
            .accessibilityValue("\(post.engagement.commentCount)")
            .accessibilityIdentifier("activityCard.comments")
            .frame(maxWidth: .infinity)

            ShareLink(item: ActivityFormatters.shareText(for: post)) {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Partager")
            .accessibilityIdentifier("activityCard.share")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .font(.subheadline.weight(.medium))
        .monospacedDigit()
        .frame(minHeight: 44)
    }
}
