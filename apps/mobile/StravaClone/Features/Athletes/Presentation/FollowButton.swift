import SwiftUI

/// The follow button (ADR-036 §1, §10), on a profile, a followers or following list and the
/// search: "Suivre" (filled), "Demande envoyée" (a tap cancels the request), or "Abonné ▾" (a
/// menu with "Se désabonner"). Shows the status it is given: a `FollowStore` makes it
/// optimistic.
struct FollowButton: View {
    let status: FollowStatus
    var controlSize: ControlSize = .regular
    /// The athlete's name, for VoiceOver ("Suivre Marie"); nil: the visible title alone.
    var athleteName: String?
    let onFollow: () -> Void
    /// "Se désabonner", or a tap on "Demande envoyée".
    let onUnfollow: () -> Void

    var body: some View {
        Group {
            switch status {
            case .none:
                Button(AthletesMessages.follow, action: onFollow)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .accessibilityLabel(athleteName.map(AthletesMessages.followLabel) ?? AthletesMessages.follow)
                    .accessibilityIdentifier("followButton.follow")
            case .pending:
                Button(AthletesMessages.requestSent, action: onUnfollow)
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                    .accessibilityLabel(athleteName.map(AthletesMessages.requestSentLabel) ?? AthletesMessages.requestSent)
                    .accessibilityHint(Text(AthletesMessages.cancelRequestHint))
                    .accessibilityIdentifier("followButton.pending")
            case .accepted:
                Menu {
                    Button(AthletesMessages.unfollow, role: .destructive, action: onUnfollow)
                } label: {
                    HStack(spacing: 4) {
                        Text(AthletesMessages.following)
                        Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.bordered)
                .tint(.secondary)
                .accessibilityLabel(athleteName.map(AthletesMessages.followingLabel) ?? AthletesMessages.following)
                .accessibilityIdentifier("followButton.following")
            }
        }
        .controlSize(controlSize)
        .fontWeight(.semibold)
        .animation(.default, value: status)
    }
}

extension FollowButton {
    /// The button of a list row or a search result: its status and changes go through `store`;
    /// nothing for the viewer themself.
    @MainActor @ViewBuilder
    static func row(athleteId: String, athleteName: String? = nil, store: FollowStore) -> some View {
        if let status = store.status(of: athleteId) {
            FollowButton(
                status: status,
                controlSize: .small,
                athleteName: athleteName,
                onFollow: { Task { await store.follow(athleteId) } },
                onUnfollow: { Task { await store.unfollow(athleteId) } }
            )
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        FollowButton(status: .none, onFollow: {}, onUnfollow: {})
        FollowButton(status: .pending, onFollow: {}, onUnfollow: {})
        FollowButton(status: .accepted, onFollow: {}, onUnfollow: {})
    }
    .padding()
}
