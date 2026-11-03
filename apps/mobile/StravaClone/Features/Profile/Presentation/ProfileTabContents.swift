import SwiftUI

/// Activités (ADR-036 §3): my Activities as the feed's cards; a tap opens the detail and the
/// comment button the Kudos and comments screen.
struct ProfileActivitiesTab: View {
    let store: ProfileActivitiesStore
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
                ActivityCard(post: post, onComments: { openComments(post.id) })
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
    }
}

/// Plus (ADR-036 §3): Statistiques with this year's distance, and my Itineraries.
struct ProfileMoreTab: View {
    let yearToDateDistance: Distance?
    let itineraryCount: Int?
    let openStatistics: @MainActor () -> Void
    let openItineraries: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: openStatistics) {
                row(
                    title: ProfileMessages.statistics,
                    subtitle: ProfileMessages.thisYear(yearToDateDistance),
                    systemImage: "chart.bar",
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.statistics")
            Divider().padding(.leading, 56)
            Button(action: openItineraries) {
                row(
                    title: itineraryCount.map { "\(ProfileMessages.itineraries) · \($0)" } ?? ProfileMessages.itineraries,
                    subtitle: nil,
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.itineraries")
        }
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        .padding(.horizontal, Theme.spacing)
    }

    private func row(title: String, subtitle: String?, systemImage: String, showsChevron: Bool = false) -> some View {
        HStack(spacing: Theme.spacing) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 24)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
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
