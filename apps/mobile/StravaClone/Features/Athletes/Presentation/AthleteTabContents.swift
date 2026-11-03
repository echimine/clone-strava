import SwiftUI

/// Activités (ADR-036 §3): their Activities the viewer may see, as the feed's cards; a tap
/// opens the detail, the comment button the Kudos and comments screen, and the kudos button
/// gives kudos.
struct AthleteActivitiesTab: View {
    let store: AthleteActivitiesStore
    let openActivity: @MainActor (ActivityID) -> Void
    let openComments: @MainActor (ActivityID) -> Void
    let retry: @MainActor () async -> Void

    var body: some View {
        switch store.phase {
        case .idle, .loading where store.posts.isEmpty:
            ProgressView().padding(.top, 40)
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
                    onComments: { openComments(post.id) }
                )
                .contentShape(.rect(cornerRadius: 20))
                .onTapGesture { openActivity(post.id) }
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
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        .padding(.horizontal, Theme.spacing)
        .accessibilityIdentifier("athleteProfile.statistics")
    }

    private func row(showsChevron: Bool) -> some View {
        HStack(spacing: Theme.spacing) {
            Image(systemName: "chart.bar")
                .font(.title3)
                .frame(width: 24)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(AthletesMessages.statistics).font(.body.weight(.semibold))
                Text(AthletesMessages.thisYear(yearToDateDistance))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(Theme.spacing)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
