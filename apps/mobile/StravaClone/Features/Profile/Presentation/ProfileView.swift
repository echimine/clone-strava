import SwiftUI

/// Profile tab (ADR-036 §3, §10): my header, then Progrès · Activités · Plus, with the
/// magnifier and the gear to Réglages at the top right. The header scrolls away and leaves my
/// name in the navigation bar. Knows nothing of other features (ADR-007 rule 5): the app shell
/// passes the search, "Mes Itinéraires" (ADR-030), the Activity detail and the Kudos and
/// comments screen pushed in this tab's own stack, and what a sign-out would lose (ADR-030 §8).
struct ProfileView<Itineraries: View, ActivityDestination: View, EngagementDestination: View>: View {
    @Bindable var store: ProfileStore
    let authStore: AuthStore
    let consent: MeasurementConsentStore
    var signOutWarning: @MainActor () async -> String? = { nil }
    var beforeSignOut: @MainActor () async -> Void = {}
    /// Debug builds only: the app shell passes its animations preview screen.
    var animationsPreview: AnyView?
    /// The magnifier: athlete search, once it exists.
    var onSearch: () -> Void = {}
    @ViewBuilder var itineraries: () -> Itineraries
    @ViewBuilder var openActivity: (ActivityDetailRequest) -> ActivityDestination
    @ViewBuilder var openEngagement: (ActivityEngagementRequest) -> EngagementDestination

    @State private var isEditingName = false
    /// The header has scrolled away: the name shows in the navigation bar.
    @State private var isHeaderHidden = false

    private var userId: String? {
        if case .signedIn(let user) = authStore.state { user.id } else { nil }
    }

    var body: some View {
        NavigationStack(path: $store.path) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
                .navigationTitle(isHeaderHidden ? store.profile?.athlete.displayName ?? "" : "")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .task(id: userId) {
                    if let userId { await store.load(athleteId: userId) }
                }
                .sheet(isPresented: $isEditingName) {
                    EditProfileSheet(store: store, displayName: store.profile?.athlete.displayName ?? "")
                }
                .navigationDestination(for: ProfileStore.Destination.self) { destination in
                    switch destination {
                    case .settings:
                        SettingsView(
                            store: store,
                            authStore: authStore,
                            consent: consent,
                            signOutWarning: signOutWarning,
                            beforeSignOut: beforeSignOut,
                            animationsPreview: animationsPreview
                        )
                    case .itineraries:
                        itineraries()
                    }
                }
                .navigationDestination(for: ActivityDetailRequest.self) { request in
                    openActivity(request)
                }
                .navigationDestination(for: ActivityEngagementRequest.self) { request in
                    openEngagement(request)
                }
        }
        .toast($store.toast)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button(action: onSearch) {
                Image(systemName: "magnifyingglass")
            }
            .accessibilityLabel(ProfileMessages.search)
            .accessibilityIdentifier("profile.search")
            Button(action: store.openSettings) {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel(ProfileMessages.settings)
            .accessibilityIdentifier("profile.settings")
        }
    }

    @ViewBuilder private var content: some View {
        switch store.phase {
        case .idle, .loading where store.profile == nil:
            ProgressView()
        case .failed(let message) where store.profile == nil:
            ContentUnavailableView {
                Label(ProfileMessages.errorTitle, systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button(ProfileMessages.retry) { Task { await store.refresh() } }
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
            LazyVStack(spacing: Theme.spacing, pinnedViews: .sectionHeaders) {
                ProfileHeader(profile: profile) { isEditingName = true }
                    .padding(.horizontal, Theme.spacing)
                    .onScrolledAway { isHeaderHidden = $0 }
                Section {
                    tabContent(profile)
                } header: {
                    Picker(selection: $store.tab) {
                        ForEach(ProfileStore.Tab.allCases, id: \.self) { tab in
                            Text(ProfileMessages.tab(tab)).tag(tab)
                        }
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, Theme.spacing)
                    .padding(.vertical, 8)
                    .background(Color(.systemGroupedBackground))
                    .accessibilityIdentifier("profile.tabs")
                }
            }
            .padding(.vertical, 8)
        }
        .refreshable { await store.refresh() }
        .accessibilityIdentifier("profile.page")
    }

    @ViewBuilder private func tabContent(_ profile: AthleteProfile) -> some View {
        switch store.tab {
        case .progress:
            ProfileProgressTab()
        case .activities:
            ProfileActivitiesTab(
                store: store.activities,
                openActivity: store.openActivity,
                openComments: store.openComments,
                retry: store.refresh
            )
        case .more:
            ProfileMoreTab(
                yearToDateDistance: store.yearToDateDistance,
                itineraryCount: profile.itineraryCount,
                openItineraries: store.openItineraries
            )
        }
    }
}

private extension View {
    /// Reports whether this view has scrolled above the top of the screen (iOS 18 and later;
    /// on iOS 17 the name stays out of the navigation bar).
    @ViewBuilder func onScrolledAway(_ action: @escaping (Bool) -> Void) -> some View {
        if #available(iOS 18.0, *) {
            onScrollVisibilityChange(threshold: 0.2) { isVisible in action(!isVisible) }
        } else {
            self
        }
    }
}
