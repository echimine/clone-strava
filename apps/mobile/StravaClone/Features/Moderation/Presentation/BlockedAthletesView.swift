import SwiftUI

/// Réglages > "Athlètes bloqués" (ADR-038 §8): Avatar and name of each athlete the viewer
/// blocked, with "Débloquer" after a confirmation.
struct BlockedAthletesView: View {
    @State private var store: BlockedAthletesStore

    init(makeStore: @MainActor () -> BlockedAthletesStore) {
        _store = State(initialValue: makeStore())
    }

    var body: some View {
        content
            .navigationTitle(ModerationMessages.blockedAthletes)
            .navigationBarTitleDisplayMode(.inline)
            .task { await store.load() }
            .toast($store.toast)
            .confirmationDialog(
                ModerationMessages.unblockConfirmationTitle(store.unblockCandidate?.athlete.firstName ?? ""),
                isPresented: Binding(
                    get: { store.unblockCandidate != nil },
                    set: { if !$0 { store.unblockCandidate = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(ModerationMessages.unblock, role: .destructive) { Task { await store.confirmUnblock() } }
                    .accessibilityIdentifier("blockedAthletes.confirmUnblock")
                Button(ModerationMessages.cancel, role: .cancel) { store.unblockCandidate = nil }
            } message: {
                Text(ModerationMessages.unblockConfirmationMessage)
            }
            .accessibilityIdentifier("blockedAthletes")
    }

    @ViewBuilder private var content: some View {
        switch store.phase {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label(ModerationMessages.loadFailedTitle, systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button(ModerationMessages.retry) { Task { await store.load() } }
                    .buttonStyle(.borderedProminent)
            }
        case .loaded where store.athletes.isEmpty:
            ContentUnavailableView(
                ModerationMessages.noBlockedAthletes,
                systemImage: "hand.raised",
                description: Text(ModerationMessages.noBlockedAthletesDetail)
            )
        case .loaded:
            List(store.athletes) { blocked in
                HStack(spacing: 12) {
                    AvatarView(name: blocked.athlete.displayName, url: blocked.athlete.avatarURL, size: 40)
                        .accessibilityHidden(true)
                    Text(blocked.athlete.displayName)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Button(ModerationMessages.unblock) { store.unblockCandidate = blocked }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("blockedAthletes.unblock")
                }
            }
            .refreshable { await store.load() }
        }
    }
}
