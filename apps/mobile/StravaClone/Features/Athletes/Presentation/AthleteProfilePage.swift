import SwiftUI

/// Another athlete's profile (ADR-036 §3, §10), pushed in the current tab's stack: back and "⋯"
/// ("Signaler", "Bloquer", ADR-038 §8, §9; once blocked, the profile closes), their header,
/// counters and follow button, then Activités · Galerie · Plus.
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
    @Environment(\.reportContent) private var reportContent
    @Environment(\.blockAthlete) private var blockAthlete
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

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
            .toolbar { moreMenu }
            .task { await store.load() }
            // Back from a pushed screen or the foreground: catches up silently once stale.
            .onAppear { Task { await store.refreshIfStale() } }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await store.refreshIfStale() } }
            }
            .toast(Binding(get: { store.follows.toast }, set: { store.follows.toast = $0 }))
            .toast(Binding(get: { store.activities.notice }, set: { store.activities.notice = $0 }))
            .toast(Binding(get: { store.gallery.notice }, set: { store.gallery.notice = $0 }))
            // Not a task of the tab's content: it would run again back from a detail.
            .onChange(of: store.tab) { _, tab in
                if tab == .gallery { Task { await store.openGallery() } }
            }
            // Their own cards' author is this profile: no new push of the same page.
            .environment(\.openAthlete, openAthlete.map { outer in
                OpenAthleteAction { [athleteId = store.athleteId] id in
                    if id != athleteId { outer(id) }
                }
            })
            .accessibilityIdentifier("athleteProfile")
    }

    /// "⋯": "Signaler" and "Bloquer". Never on one's own profile, which is the Profile tab.
    @ToolbarContentBuilder private var moreMenu: some ToolbarContent {
        if let athlete = store.profile?.athlete, reportContent != nil || blockAthlete != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let reportContent {
                        // A reported athlete is never hidden by the Report itself, only by "Bloquer aussi".
                        Button(ModerationLabels.report, systemImage: ModerationLabels.reportImage) {
                            reportContent(.athlete(athlete)) { hiding in
                                if hiding == .author { dismiss() }
                            }
                        }
                        .accessibilityIdentifier("athleteProfile.report")
                    }
                    if let blockAthlete {
                        Button(ModerationLabels.block, systemImage: ModerationLabels.blockImage, role: .destructive) {
                            blockAthlete(athlete) { dismiss() }
                        }
                        .accessibilityIdentifier("athleteProfile.block")
                    }
                } label: {
                    Label(AthletesMessages.more, systemImage: "ellipsis")
                }
                .accessibilityIdentifier("athleteProfile.more")
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch store.phase {
        case .idle, .loading where store.profile == nil:
            ProgressView()
                .accessibilityLabel("Chargement")
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
                            athleteName: profile.athlete.displayName,
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
                openKudos: { openEngagement(.kudos($0)) },
                retry: { await store.refresh() }
            )
            .groupedTabContent()
        case .gallery:
            AthleteGalleryTab(store: store.gallery) { openActivity(ActivityDetailRequest(id: $0)) }
        case .more:
            AthleteMoreTab(yearToDateDistance: store.yearToDateDistance, openStatistics: statisticsAction(profile))
        }
    }

    private static func systemImage(_ tab: AthleteProfileStore.Tab) -> String {
        switch tab {
        case .activities: "waveform.path.ecg"
        case .gallery: GalleryMessages.systemImage
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
