import SwiftUI

/// Overlapping avatars of kudos givers, the most recent first (on top) (ADR-036 §5).
struct KudosAvatarStack: View {
    let givers: [ActivityAuthor]
    var size: CGFloat = 24
    /// The ring that separates two avatars, the colour of what is behind them.
    var ring = Color(.secondarySystemGroupedBackground)

    var body: some View {
        HStack(spacing: -size / 4) {
            ForEach(Array(givers.enumerated()), id: \.element.id) { index, giver in
                AvatarView(name: giver.displayName, url: giver.avatarURL, size: size)
                    .overlay(Circle().stroke(ring, lineWidth: 2))
                    .zIndex(Double(givers.count - index))
            }
        }
        .accessibilityHidden(true)
    }
}
