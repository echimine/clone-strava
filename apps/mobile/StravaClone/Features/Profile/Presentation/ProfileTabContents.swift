import SwiftUI

/// Activités (ADR-036 §3): my Activities as the feed's cards; a tap opens the detail and the
/// comment button the Kudos and comments screen.
struct ProfileActivitiesTab: View {
    @Bindable var store: ProfileActivitiesStore
    let openActivity: @MainActor (ActivityID) -> Void
    let openComments: @MainActor (ActivityID) -> Void
    let retry: @MainActor () async -> Void

    var body: some View {
        switch store.phase {
        case .idle, .loading where store.posts.isEmpty:
            ProgressView().padding(.top, 40)
        case .failed(let message) where store.posts.isEmpty:
            ContentUnavailableView {
                Label(ProfileMessages.errorTitle, systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button(ProfileMessages.retry) { Task { await retry() } }
                    .buttonStyle(.borderedProminent)
            }
        default:
            if store.isEmpty {
                ContentUnavailableView(
                    ProfileMessages.emptyActivitiesTitle,
                    systemImage: "figure.run",
                    description: Text(ProfileMessages.emptyActivitiesDescription)
                )
                .padding(.top, 40)
            } else {
                cards
            }
        }
    }

    private var cards: some View {
        LazyVStack(spacing: Theme.spacing) {
            ForEach(store.posts) { post in
                // My own cards: the kudos button is disabled (ADR-029).
                ActivityCard(post: post, onComments: { openComments(post.id) }, onTapMedia: { store.openMedia($0, of: post.id) })
                    .contentShape(.rect(cornerRadius: 20))
                    .onTapGesture { openActivity(post.id) }
                    .accessibilityAction(named: Text("Ouvrir l'activité")) { openActivity(post.id) }
                    .task { await store.loadMoreIfNeeded(currentPost: post) }
            }
            if store.isLoadingMore {
                ProgressView().padding()
            }
        }
        .animation(.default, value: store.posts.map(\.id))
        .padding(.horizontal, Theme.spacing)
        .accessibilityIdentifier("profile.activities")
        .mediaViewer($store.mediaViewer)
    }
}

/// Plus (ADR-036 §3), as Strava's list: Statistiques with this year's distance, and my
/// Itineraries with their count.
struct ProfileMoreTab: View {
    let yearToDateDistance: Distance?
    let itineraryCount: Int?
    let openStatistics: @MainActor () -> Void
    let openItineraries: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: openStatistics) {
                ProfileMenuRow(
                    title: ProfileMessages.statistics,
                    subtitle: ProfileMessages.thisYear(yearToDateDistance),
                    systemImage: "list.bullet.rectangle"
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.statistics")
            Button(action: openItineraries) {
                ProfileMenuRow(
                    title: ProfileMessages.itineraries,
                    subtitle: itineraryCount.map { $0.formatted() },
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.itineraries")
        }
        .padding(.vertical, 8)
    }
}
