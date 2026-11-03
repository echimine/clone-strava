import SwiftUI

/// The follow button (ADR-036 §1, §10), on a profile, a followers or following list and the
/// search: "Suivre" (filled), "Demande envoyée" (a tap cancels the request), or "Abonné ▾" (a
/// menu with "Se désabonner"). Shows the status it is given: a `FollowStore` makes it
/// optimistic.
struct FollowButton: View {
    let status: FollowStatus
    var controlSize: ControlSize = .regular
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
                    .accessibilityIdentifier("followButton.follow")
            case .pending:
                Button(AthletesMessages.requestSent, action: onUnfollow)
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                    .accessibilityHint(Text(AthletesMessages.cancelRequestHint))
                    .accessibilityIdentifier("followButton.pending")
            case .accepted:
                Menu {
                    Button(AthletesMessages.unfollow, role: .destructive, action: onUnfollow)
                } label: {
                    HStack(spacing: 4) {
                        Text(AthletesMessages.following)
                        Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.bordered)
                .tint(.secondary)
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
    static func row(athleteId: String, store: FollowStore) -> some View {
        if let status = store.status(of: athleteId) {
            FollowButton(
                status: status,
                controlSize: .small,
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
