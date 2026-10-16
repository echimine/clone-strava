import SwiftUI

/// Everyone who gave kudos, most recent first, loaded page by page (ADR-034 §1). Athletes are
/// not tappable: there is no athlete profile yet.
struct KudosListSheet: View {
    let store: KudosListStore

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(ActivityDetailMessages.kudosTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("OK") { dismiss() }
                    }
                }
        }
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
        case .loaded:
            List {
                ForEach(store.givers) { giver in
                    HStack(spacing: 12) {
                        AvatarView(name: giver.athlete.displayName, url: giver.athlete.avatarURL, size: 40)
                        Text(giver.athlete.displayName)
                            .font(.body)
                    }
                    .accessibilityElement(children: .combine)
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
