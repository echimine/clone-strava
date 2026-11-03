import SwiftUI

/// Another athlete's profile (ADR-036 §3, §10), pushed in the current tab's stack: back (no "⋯":
/// "Partager le profil" is not shown and nothing else goes there), their header, counters and
/// follow button, then Activités · Plus.
/// Knows nothing of other features (ADR-007 rule 5): the app shell pushes the Activity detail,
/// the Kudos and comments screen and the Statistiques screen.
struct AthleteProfilePage: View {
    @State private var store: AthleteProfileStore
    private let openActivity: @MainActor (ActivityDetailRequest) -> Void
    private let openEngagement: @MainActor (ActivityEngagementRequest) -> Void
    /// Plus > Statistiques; nil: the row is shown, not tappable.
    private let openStatistics: (@MainActor (AthleteProfile) -> Void)?
    /// Their counters: the followers and following lists; nil: not tappable.
    private let openFollows: (@MainActor (AthleteFollowsRequest) -> Void)?

    @Environment(\.openAthlete) private var openAthlete

    init(
        request: AthleteProfileRequest,
        makeStore: @MainActor (String) -> AthleteProfileStore,
        openActivity: @escaping @MainActor (ActivityDetailRequest) -> Void,
        openEngagement: @escaping @MainActor (ActivityEngagementRequest) -> Void,
        openStatistics: (@MainActor (AthleteProfile) -> Void)? = nil,
        openFollows: (@MainActor (AthleteFollowsRequest) -> Void)? = nil
    ) {
        _store = State(initialValue: makeStore(request.id))
        self.openActivity = openActivity
        self.openEngagement = openEngagement
        self.openStatistics = openStatistics
        self.openFollows = openFollows
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .navigationTitle(store.profile?.athlete.displayName ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .task { await store.load() }
            .toast(Binding(get: { store.follows.toast }, set: { store.follows.toast = $0 }))
            .toast(Binding(get: { store.activities.notice }, set: { store.activities.notice = $0 }))
            // Their own cards' author is this profile: no new push of the same page.
            .environment(\.openAthlete, openAthlete.map { outer in
                OpenAthleteAction { [athleteId = store.athleteId] id in
                    if id != athleteId { outer(id) }
                }
            })
            .accessibilityIdentifier("athleteProfile")
    }

    @ViewBuilder private var content: some View {
        switch store.phase {
        case .idle, .loading where store.profile == nil:
            ProgressView()
        case .failed(let message) where store.profile == nil:
            ContentUnavailableView {
                Label(AthletesMessages.errorTitle, systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button(AthletesMessages.retry) { Task { await store.refresh() } }
                    .buttonStyle(.borderedProminent)
            }
        default:
            if let profile = store.profile {
                page(profile)
            }
        }
    }

    private func page(_ profile: AthleteProfile) -> some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                AthleteProfileHeader(profile: profile, onFollows: followsAction(profile)) {
                    if let status = store.followStatus {
                        FollowButton(
                            status: status,
                            controlSize: .large,
                            onFollow: { Task { await store.follow() } },
                            onUnfollow: { Task { await store.unfollow() } }
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, Theme.spacing)
                .padding(.bottom, 20)
                Section {
                    tabContent(profile)
                } header: {
                    ProfileTabBar(
                        tabs: AthleteProfileStore.Tab.allCases,
                        selection: $store.tab,
                        title: AthletesMessages.tab,
                        systemImage: Self.systemImage
                    )
                    .accessibilityIdentifier("athleteProfile.tabs")
                }
            }
            .padding(.top, 8)
        }
        .refreshable { await store.refresh() }
        // ADR-037 §1: an expired pre-signed Media or Avatar URL brings fresh ones.
        .onImageURLExpired { await store.refresh() }
    }

    @ViewBuilder private func tabContent(_ profile: AthleteProfile) -> some View {
        switch store.tab {
        case .activities:
            AthleteActivitiesTab(
                store: store.activities,
                openActivity: { openActivity(ActivityDetailRequest(id: $0)) },
                openComments: { openEngagement(.comments($0)) },
                retry: { await store.refresh() }
            )
            .groupedTabContent()
        case .more:
            AthleteMoreTab(yearToDateDistance: store.yearToDateDistance, openStatistics: statisticsAction(profile))
        }
    }

    private static func systemImage(_ tab: AthleteProfileStore.Tab) -> String {
        switch tab {
        case .activities: "waveform.path.ecg"
        case .more: "line.3.horizontal"
        }
    }

    private func followsAction(_ profile: AthleteProfile) -> ((AthleteFollowsRequest.Kind) -> Void)? {
        guard let openFollows else { return nil }
        return { openFollows(AthleteFollowsRequest(profile: profile, list: $0)) }
    }

    private func statisticsAction(_ profile: AthleteProfile) -> (@MainActor () -> Void)? {
        guard let openStatistics else { return nil }
        return { openStatistics(profile) }
    }
}
