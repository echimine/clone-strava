import SwiftUI

/// Activités (ADR-036 §3): their Activities the viewer may see, as the feed's cards; a tap
/// opens the detail, the comment button the Kudos and comments screen, and the kudos button
/// gives kudos.
struct AthleteActivitiesTab: View {
    @Bindable var store: AthleteActivitiesStore
    let openActivity: @MainActor (ActivityID) -> Void
    let openComments: @MainActor (ActivityID) -> Void
    let openKudos: @MainActor (ActivityID) -> Void
    let retry: @MainActor () async -> Void

    var body: some View {
        switch store.phase {
        case .idle, .loading where store.posts.isEmpty:
            ProgressView().accessibilityLabel("Chargement").padding(.top, 40)
        case .failed(let message) where store.posts.isEmpty:
            ContentUnavailableView {
                Label(AthletesMessages.errorTitle, systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button(AthletesMessages.retry) { Task { await retry() } }
                    .buttonStyle(.borderedProminent)
            }
        default:
            if store.isEmpty {
                ContentUnavailableView(
                    AthletesMessages.emptyActivitiesTitle,
                    systemImage: "figure.run",
                    description: Text(AthletesMessages.emptyActivitiesDescription)
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
                ActivityCard(
                    post: post,
                    onToggleKudos: { Task { await store.toggleKudos(on: post.id) } },
                    onComments: { openComments(post.id) },
                    onShowKudos: { openKudos(post.id) },
                    onTapMedia: { store.openMedia($0, of: post.id) }
                )
                .contentShape(.rect(cornerRadius: 20))
                .onTapGesture { openActivity(post.id) }
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: Text(AthletesMessages.openActivity)) { openActivity(post.id) }
                .task { await store.loadMoreIfNeeded(currentPost: post) }
            }
            if store.isLoadingMore {
                ProgressView().padding()
            }
        }
        .animation(.default, value: store.posts.map(\.id))
        .padding(.horizontal, Theme.spacing)
        .accessibilityIdentifier("athleteProfile.activities")
        .mediaViewer($store.mediaViewer)
    }
}

/// Plus (ADR-036 §3): their Statistiques, with this year's distance. The row opens the
/// Statistiques screen when the app shell gives one.
struct AthleteMoreTab: View {
    let yearToDateDistance: Distance?
    let openStatistics: (@MainActor () -> Void)?

    var body: some View {
        Group {
            if let openStatistics {
                Button(action: openStatistics) { row(showsChevron: true) }
                    .buttonStyle(.plain)
            } else {
                row(showsChevron: false)
            }
        }
        .padding(.vertical, 8)
        .accessibilityIdentifier("athleteProfile.statistics")
    }

    private func row(showsChevron: Bool) -> some View {
        ProfileMenuRow(
            title: AthletesMessages.statistics,
            subtitle: AthletesMessages.thisYear(yearToDateDistance),
            systemImage: "list.bullet.rectangle",
            showsChevron: showsChevron
        )
    }
}
