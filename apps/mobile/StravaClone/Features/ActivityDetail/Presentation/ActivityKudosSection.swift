import SwiftUI

/// The detail's kudos row and action bar (ADR-036 §9 point 7). The row (the most recent
/// givers, then "N ont envoyé des kudos") opens the Kudos and comments screen on Kudos (§8);
/// it is hidden without kudos. The bar: the kudos button (not on the viewer's own Activity),
/// comments with their count (that screen on Commentaires, composer focused) and share.
struct ActivityKudosSection: View {
    let store: ActivityDetailStore
    let detail: ActivityDetail

    private var engagement: ActivityEngagement { detail.engagement }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let summary = ActivityCardMessages.socialSummary(kudosCount: engagement.kudosCount, commentCount: 0) {
                kudosRow(summary)
                Divider()
            }
            actionBar
        }
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }

    private func kudosRow(_ summary: String) -> some View {
        NavigationLink(value: ActivityEngagementRequest.kudos(store.id)) {
            HStack(spacing: 12) {
                if !store.recentKudos.isEmpty {
                    KudosAvatarStack(givers: store.recentKudos.map(\.athlete), size: 32)
                        .accessibilityIdentifier("activityDetail.kudosAvatars")
                }
                Text(summary)
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Theme.spacing)
            .frame(minHeight: 52)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
        .accessibilityHint("Afficher qui a donné un kudos")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("activityDetail.kudosList")
    }

    private var actionBar: some View {
        HStack(spacing: 0) {
            if store.showsKudosButton {
                kudosButton
            }
            commentsButton
            ShareLink(item: ActivityFormatters.shareText(for: detail.post)) {
                Image(systemName: "square.and.arrow.up")
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Partager")
            .accessibilityIdentifier("activityDetail.share")
        }
        .buttonStyle(.plain)
        .font(.title3)
        .foregroundStyle(.primary)
    }

    private var commentsButton: some View {
        NavigationLink(value: ActivityEngagementRequest.comments(store.id)) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left")
                if engagement.commentCount > 0 {
                    Text(engagement.commentCount.formatted())
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(.rect)
        }
        .accessibilityLabel(ActivityEngagementMessages.commentsButton(engagement.commentCount))
        .accessibilityIdentifier("activityDetail.comments")
    }

    private var kudosButton: some View {
        Button {
            Task { await store.toggleKudos() }
        } label: {
            Image(systemName: engagement.viewerHasKudoed ? "hand.thumbsup.fill" : "hand.thumbsup")
                .foregroundStyle(engagement.viewerHasKudoed ? Theme.accent : .primary)
                .contentTransition(.symbolEffect(.replace))
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(.rect)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: engagement.viewerHasKudoed)
        .accessibilityLabel(engagement.viewerHasKudoed ? "Retirer le kudos" : "Donner un kudos")
        .accessibilityIdentifier("activityDetail.kudos")
    }
}
