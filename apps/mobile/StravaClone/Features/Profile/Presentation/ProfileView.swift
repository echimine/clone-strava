import SwiftUI

/// Profile tab (ADR-036 §3, §10), laid out as Strava: my header on white, then the Progrès ·
/// Activités · Galerie · Plus tabs with their icons, with the magnifier and the gear to Réglages at the top right. The header scrolls away and leaves my
/// name in the navigation bar. Knows nothing of other features (ADR-007 rule 5): the app shell
/// passes the signed-in account and the sign-out, the search, "Mes Itinéraires" (ADR-030), the
/// screens every tab's stack pushes (`AppDestinations`: the Activity detail, the Kudos and
/// comments screen, Statistiques, the followers and following lists and another athlete's
/// profile), and what a sign-out would lose (ADR-030 §8).
struct ProfileView<Itineraries: View, Search: View>: View {
    @Bindable var store: ProfileStore
    let account: ProfileAccount?
    let signOut: @MainActor () async -> Void
    var signOutWarning: @MainActor () async -> String? = { nil }
    var beforeSignOut: @MainActor () async -> Void = {}
    /// Debug builds only: the app shell passes its animations preview screen.
    var animationsPreview: AnyView?
    /// Réglages > "Athlètes bloqués" (ADR-038 §8), from the app shell.
    var blockedAthletes: AnyView?
    /// Réglages > « Supprimer mon compte » (ADR-038 §13), a new screen each time it is pushed.
    var accountDeletion: (() -> AnyView)?
    let destinations: AppDestinations
    @ViewBuilder var itineraries: () -> Itineraries
    /// The magnifier: the athlete search (ADR-036 §2).
    @ViewBuilder var search: () -> Search

    @State private var isEditingName = false
    /// The photo menu, from a tap on my avatar (ADR-037 §2).
    @State private var isChoosingPhoto = false
    /// The header has scrolled away: the name shows in the navigation bar.
    @State private var isHeaderHidden = false

    private var userId: String? { account?.id }

    var body: some View {
        NavigationStack(path: $store.path) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
                .navigationTitle(isHeaderHidden ? store.profile?.athlete.displayName ?? "" : "")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .task(id: userId) {
                    if let userId { await store.load(athleteId: userId) }
                }
                // Not a task of the tab's content: it would run again back from a detail.
                .onChange(of: store.tab) { _, tab in
                    if tab == .gallery { Task { await store.openGallery() } }
                }
                .avatarPicker(
                    isPresented: $isChoosingPhoto,
                    hasPhoto: store.profile?.athlete.avatarURL != nil,
                    editor: store.avatar,
                    entry: .profile
                )
                .fullScreenCover(isPresented: $isEditingName) {
                    EditProfileSheet(store: store)
                }
                .navigationDestination(for: ProfileStore.Destination.self) { destination in
                    switch destination {
                    case .settings:
                        SettingsView(
                            store: store,
                            account: account,
                            signOut: signOut,
                            signOutWarning: signOutWarning,
                            beforeSignOut: beforeSignOut,
                            animationsPreview: animationsPreview,
                            blockedAthletes: blockedAthletes,
                            accountDeletion: accountDeletion?()
                        )
                    case .itineraries:
                        itineraries()
                    case .search:
                        search()
                    }
                }
                .registerAppDestinations(destinations)
        }
        .toast($store.toast)
        .toast(Binding(get: { store.gallery.notice }, set: { store.gallery.notice = $0 }))
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button(action: store.openSearch) {
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
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                ProfileHeader(
                    profile: profile,
                    avatar: store.avatar,
                    onAvatar: { isChoosingPhoto = true },
                    onFollows: store.openFollows
                ) { isEditingName = true }
                    .padding(.horizontal, Theme.spacing)
                    .padding(.bottom, 20)
                    .onScrolledAway { isHeaderHidden = $0 }
                Section {
                    tabContent(profile)
                } header: {
                    ProfileTabBar(
                        tabs: ProfileStore.Tab.allCases,
                        selection: $store.tab,
                        title: ProfileMessages.tab,
                        systemImage: Self.systemImage
                    )
                    .accessibilityIdentifier("profile.tabs")
                }
            }
            .padding(.top, 8)
        }
        .refreshable { await store.refresh() }
        // ADR-037 §1: an expired pre-signed Media or Avatar URL brings fresh ones.
        .onImageURLExpired { await store.refresh() }
        .accessibilityIdentifier("profile.page")
    }

    @ViewBuilder private func tabContent(_ profile: AthleteProfile) -> some View {
        switch store.tab {
        case .progress:
            ProfileProgressTab(store: store.progress, practicedSports: profile.practicedSports)
                .groupedTabContent()
        case .activities:
            ProfileActivitiesTab(
                store: store.activities,
                openActivity: store.openActivity,
                openComments: store.openComments,
                retry: store.refresh
            )
            .groupedTabContent()
        case .gallery:
            AthleteGalleryTab(store: store.gallery, openActivity: store.openActivity)
        case .more:
            ProfileMoreTab(
                yearToDateDistance: store.yearToDateDistance,
                itineraryCount: profile.itineraryCount,
                openStatistics: store.openStatistics,
                openItineraries: store.openItineraries
            )
        }
    }

    private static func systemImage(_ tab: ProfileStore.Tab) -> String {
        switch tab {
        case .progress: "chart.bar.doc.horizontal"
        case .activities: "waveform.path.ecg"
        case .gallery: GalleryMessages.systemImage
        case .more: "line.3.horizontal"
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
