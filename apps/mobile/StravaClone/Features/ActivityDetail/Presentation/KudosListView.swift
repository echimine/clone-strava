import SwiftUI

/// The Kudos segment of the Kudos and comments screen (ADR-036 §8): everyone who gave kudos,
/// most recent first, loaded page by page (ADR-034 §1).
struct KudosListView: View {
    let store: KudosListStore

    var body: some View {
        content
            .task { await store.load() }
            .accessibilityIdentifier("kudosList")
    }

    @ViewBuilder private var content: some View {
        switch store.phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label(ActivityDetailMessages.errorTitle, systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button(ActivityDetailMessages.retry) { Task { await store.load() } }
                    .buttonStyle(.borderedProminent)
            }
        case .loaded where store.givers.isEmpty:
            ContentUnavailableView(ActivityEngagementMessages.noKudos, systemImage: "hand.thumbsup")
        case .loaded:
            List {
                ForEach(store.givers) { giver in
                    // The row opens the giver's profile (ADR-036 §8).
                    AthleteButton(athlete: giver.athlete) {
                        HStack(spacing: 12) {
                            AvatarView(name: giver.athlete.displayName, url: giver.athlete.avatarURL, size: 40)
                            Text(giver.athlete.displayName)
                                .font(.body)
                            Spacer(minLength: 0)
                        }
                        .contentShape(.rect)
                    }
                    .accessibilityIdentifier("kudosList.athlete")
                    .task { await store.loadMoreIfNeeded(current: giver) }
                }
                if store.isLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
        }
    }
}
