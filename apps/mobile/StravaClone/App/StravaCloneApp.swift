import GoogleSignIn
import SwiftUI

@main
struct StravaCloneApp: App {
    /// Owns the composition root, built before `didFinishLaunchingWithOptions` (ADR-031 §3).
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private var di: Di { appDelegate.di }

    var body: some Scene {
        WindowGroup {
            RootView(
                authStore: di.makeAuthStore(),
                consentStore: di.makeMeasurementConsentStore(),
                makeOnboardingStore: di.makeOnboardingStore,
                makeAvatarEditor: di.makeAvatarEditor,
                makePaywallStore: di.makePaywallStore,
                recordingStore: di.makeRecordingStore(),
                importStore: di.makeImportStore(),
                feedStore: di.makeFeedStore(),
                profileStore: di.makeProfileStore(),
                makeActivityDetailStore: { [di] id in di.makeActivityDetailStore(id: id) },
                makeActivityEngagementStore: { [di] request in di.makeActivityEngagementStore(request: request) },
                makeAthleteProfileStore: { [di] id in di.makeAthleteProfileStore(athleteId: id) },
                makeAthleteStatisticsStore: { [di] request in di.makeAthleteStatisticsStore(request: request) },
                makeFollowListStore: { [di] request in di.makeFollowListStore(request: request) },
                makeAthleteSearchStore: di.makeAthleteSearchStore,
                feedActivityEditor: di.feedActivityEditor,
                activityDeleter: di.activityDeleter,
                reloadUpdatedActivities: di.makeReloadUpdatedActivities(),
                activityLiveEvents: di.activityLiveEvents,
                realtimeService: di.realtimeService,
                makeItineraryEditorStore: di.makeItineraryEditorStore,
                makeItinerarySaveStore: di.makeItinerarySaveStore,
                itineraryListStore: di.makeItineraryListStore(),
                mapItinerariesStore: di.makeMapItinerariesStore(),
                makeItineraryDetailStore: { [di] id in di.makeItineraryDetailStore(id: id, source: .profile) },
                makeItineraryEditFlow: di.makeItineraryEditFlow,
                itineraryCreation: di.makeItineraryCreationFlow(),
                itinerarySynchronizer: di.itinerarySynchronizer,
                connectivityChanges: di.connectivityChanges,
                syncCoordinator: di.syncCoordinator,
                defaultVisibility: di.defaultVisibility,
                isSplashPresented: !ProcessInfo.processInfo.arguments.contains(SplashView.disablingArgument)
            )
                .tint(Theme.accent)
                .environment(\.imageLoader, di.imageLoader)
                .environment(\.mediaUploads, di.mediaUploadQueue.board)
                .environment(\.mapboxAccessToken, di.configuration.mapboxAccessToken)
                .environment(di.locationPermission)
                .environment(\.locationProvider, di.locationProvider)
                .onOpenURL { url in
                    // Routes the Google sign-in callback back into the SDK (ADR-022).
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}

/// Gates the app behind the Welcome and its account screen (ADR-022, ADR-035): the TabView is only
/// reachable once signed in. Session is checked once at launch (`AuthStore.restoreSession`).
struct RootView: View {
    @State var authStore: AuthStore
    /// The Measurement consent (ADR-035 §8): the Welcome's sheet, the Profile tab's switch.
    @State var consentStore: MeasurementConsentStore
    /// "Créer un compte" on the Welcome: the Onboarding, resumed from its draft (ADR-035 §1, §5).
    /// With an action, the Onboarding that "Se connecter" opened on a new account, ended by it.
    let makeOnboardingStore: @MainActor ((@MainActor () -> Void)?) -> OnboardingStore
    /// The photo menu of "Ajoute une photo de profil" (ADR-037 §2), one editor for the screen.
    let makeAvatarEditor: @MainActor () -> AvatarEditor
    /// The Paywall after the sign-in that ends the Onboarding (ADR-035 §6), ended by its action;
    /// told whether that sign-in created the account.
    let makePaywallStore: @MainActor (Bool, @escaping @MainActor () -> Void) -> PaywallStore
    @State var recordingStore: RecordingStore
    @State var importStore: ImportStore
    @State var feedStore: FeedStore
    /// The Profile tab and Réglages (ADR-036 §3, §10).
    @State var profileStore: ProfileStore
    /// Details pushed from the feed's cards (ADR-033 §1).
    let makeActivityDetailStore: @MainActor (ActivityID) -> ActivityDetailStore
    /// Kudos and comments screens, pushed from a detail or a card (ADR-036 §8).
    let makeActivityEngagementStore: @MainActor (ActivityEngagementRequest) -> ActivityEngagementStore
    /// Another athlete's profile, pushed from wherever an athlete is shown (ADR-036 §10).
    let makeAthleteProfileStore: @MainActor (String) -> AthleteProfileStore
    /// Statistiques of an athlete, mine or another's (ADR-036 §4).
    let makeAthleteStatisticsStore: @MainActor (AthleteStatisticsRequest) -> AthleteStatisticsStore
    /// Followers and following lists, mine or another athlete's (ADR-036 §1).
    let makeFollowListStore: @MainActor (AthleteFollowsRequest) -> FollowListStore
    /// The search behind the profile's magnifier (ADR-036 §2).
    let makeAthleteSearchStore: @MainActor () -> AthleteSearchStore
    /// "Modifier" in the context menu of my feed cards (ADR-033 §1).
    @State var feedActivityEditor: ActivityEditor
    /// "Supprimer" in that menu and in a detail's "⋯" (ADR-033 §7); its toast shows over the feed.
    @State var activityDeleter: ActivityDeleter
    /// The feed's cards follow `activity.updated` and `activity.deleted` (ADR-033 §8).
    let reloadUpdatedActivities: ReloadUpdatedActivities
    /// What happens to an open detail elsewhere (ADR-034 §5).
    let activityLiveEvents: any ActivityLiveEventSource
    let realtimeService: RealtimeService
    let makeItineraryEditorStore: @MainActor (ItinerarySport, ItineraryID, AnalyticsEvent.EditorSource) -> ItineraryEditorStore
    let makeItinerarySaveStore: @MainActor () -> ItinerarySaveStore
    @State var itineraryListStore: ItineraryListStore
    @State var mapItinerariesStore: MapItinerariesStore
    /// Details pushed from Profil > Mes Itinéraires.
    let makeItineraryDetailStore: @MainActor (ItineraryID) -> ItineraryDetailStore
    let makeItineraryEditFlow: @MainActor (ItineraryID) -> ItineraryEditFlow
    @State var itineraryCreation: ItineraryCreationFlow
    let itinerarySynchronizer: ItinerarySynchronizer
    let connectivityChanges: @MainActor () -> AsyncStream<Bool>
    /// Sends the queued operations and follows the Activities in `processing` (ADR-031 §14).
    let syncCoordinator: SyncQueueCoordinator
    let defaultVisibility: DefaultVisibilityCache
    /// The animated splash (ADR-032 §4), over the app from the cold launch until it is revealed.
    /// It lives as long as the scene, so a return from the background does not replay it.
    @State var isSplashPresented = true

    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = AppTab.feed
    /// A queued Itinerary change the server turned down (ADR-030 §8).
    @State private var itineraryChangeToast: String?

    /// Signed-in user id while the app is in the foreground: drives the realtime connection.
    private var realtimeUserId: String? {
        guard scenePhase == .active, case .signedIn(let user) = authStore.state else { return nil }
        return user.id
    }

    /// "Démarrer avec cet Itinéraire" on an Itinerary's detail (ADR-031 §2): the Record tab,
    /// with the Itinerary chosen on the pre-start screen, or the Recording in progress.
    private var startRecordingWithItinerary: StartRecordingWithItinerary {
        StartRecordingWithItinerary(isRecording: recordingStore.snapshot != nil) { [recordingStore] id in
            selectedTab = .record
            Task { await recordingStore.prepare(itineraryID: id) }
        }
    }

    var body: some View {
        Group {
            switch authStore.state {
            case .checkingSession:
                ProgressView()
            case .signedOut:
                WelcomeView(
                    consent: consentStore,
                    isRevealed: !isSplashPresented,
                    viewed: authStore.welcomeViewed,
                    opened: { [authStore] entry in
                        if entry == .createAccount { authStore.onboardingStarted() }
                    }
                ) { entry, back in
                    switch entry {
                    case .createAccount:
                        OnboardingView(store: makeOnboardingStore(nil), leave: back, accountScreen: createAccountScreen)
                    case .signIn:
                        AccountView(mode: .signIn, authStore: authStore, onBack: back)
                    }
                }
                    .onAppear {
                        feedStore.reset()
                        profileStore.reset()
                        defaultVisibility.clear()
                        // ADR-030 §8: the Itinerary cache does not outlive the session.
                        Task { await itinerarySynchronizer.signOut() }
                    }
            case .onboarding:
                // ADR-035 §1: "Se connecter" has just created the account.
                OnboardingView(
                    store: makeOnboardingStore { [authStore] in authStore.finishOnboarding() },
                    accountScreen: createAccountScreen
                )
            case .avatarPrompt(let user):
                // ADR-037 §2: an account the email code has just created, once, then the Paywall.
                AvatarPromptView(
                    name: user.name,
                    editor: makeAvatarEditor(),
                    chosen: authStore.finishAvatarPrompt,
                    later: authStore.deferAvatarPrompt
                )
            case .paywall(let user):
                // ADR-035 §6: once, then the notification priming screen or home.
                PaywallView(
                    store: makePaywallStore(authStore.isNewAccount) { [authStore] in
                        Task { await authStore.finishPaywall() }
                    },
                    firstName: user.firstName
                )
            case .notificationPrimer:
                // ADR-035 §7: only while iOS has not asked yet, then home.
                NotificationPrimerView(
                    isRequesting: authStore.isRequestingNotifications,
                    enable: { Task { await authStore.enableNotifications() } },
                    later: authStore.deferNotifications
                )
            case .signedIn:
                TabView(selection: $selectedTab) {
                    FeedView(
                        store: feedStore,
                        onImportActivity: importStore.startImport,
                        editActivity: { [feedActivityEditor] id in Task { await feedActivityEditor.edit(id: id) } },
                        deleteActivity: { [activityDeleter] id in Task { await activityDeleter.delete(id) } },
                        destinations: appDestinations(path: $feedStore.path)
                    ) {
                        if let banner = importStore.banner {
                            ImportStatusBanner(
                                banner: banner,
                                onPickSport: importStore.pickSportAgain,
                                onDismiss: importStore.dismissBanner
                            )
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .animation(.default, value: importStore.banner)
                    .environment(\.openAthlete, openAthlete(in: $feedStore.path))
                    .activityEditing(feedActivityEditor)
                    .toast($activityDeleter.toast)
                    .fileImporter(
                        isPresented: $importStore.isPickingFile,
                        allowedContentTypes: ImportFileTypes.all,
                        onCompletion: importStore.filePicked
                    )
                    .sheet(item: $importStore.confirmation) { confirmation in
                        ImportConfirmationSheet(
                            confirmation: confirmation,
                            onConfirm: { options in Task { await importStore.confirm(options) } },
                            onCancel: importStore.cancelConfirmation
                        )
                    }
                    .tabItem { Label("Accueil", systemImage: "house") }
                    .tag(AppTab.feed)
                    NavigationStack {
                        MapScreen(
                            onCreateItinerary: { itineraryCreation.start(from: .mapTab) },
                            focusedPath: mapItinerariesStore.focusedPath
                        ) {
                            MapItinerariesCarousel(store: mapItinerariesStore)
                        }
                        .navigationDestination(for: ItineraryID.self) { [mapItinerariesStore] id in
                            ItineraryDetailPage(
                                id: id,
                                makeDetailStore: mapItinerariesStore.makeDetailStore,
                                makeEditFlow: mapItinerariesStore.makeEditFlow
                            )
                        }
                    }
                    .tabItem { Label("Map", systemImage: "map") }
                    .tag(AppTab.map)
                    RecordingView(
                        store: recordingStore,
                        onSaved: activitySaved,
                        onCreateItinerary: { itineraryCreation.start(from: .recording) }
                    )
                    .tabItem { Label("Enregistrer", systemImage: "record.circle") }
                    .tag(AppTab.record)
                    ProfileView(
                        store: profileStore,
                        account: profileAccount,
                        consent: consentStore,
                        signOut: { [authStore] in await authStore.signOut() },
                        signOutWarning: {
                            // ADR-031 §10, §14: one confirmation for all that a sign-out loses.
                            SignOutWarning.message(
                                recordingInProgress: await recordingStore.signOutWarning() != nil,
                                unsentActivities: await syncCoordinator.unsentActivityCount(),
                                pendingItineraryChanges: await itinerarySynchronizer.pendingChangeCount()
                            )
                        },
                        beforeSignOut: {
                            await recordingStore.delete()
                            await syncCoordinator.signOut()
                        },
                        animationsPreview: Self.animationsPreview,
                        destinations: appDestinations(path: $profileStore.path),
                        itineraries: {
                            MyItinerariesView(
                                store: itineraryListStore,
                                makeDetailStore: makeItineraryDetailStore,
                                makeEditFlow: makeItineraryEditFlow,
                                onCreate: { itineraryCreation.start(from: .profile) }
                            )
                        },
                        search: { AthleteSearchPage(makeStore: makeAthleteSearchStore) }
                    )
                    .environment(\.openAthlete, openAthlete(in: $profileStore.path))
                    // A detail opened from the profile can delete its Activity too (ADR-033 §7).
                    .toast($activityDeleter.toast)
                    .tabItem { Label("Profil", systemImage: "person") }
                    .tag(AppTab.profile)
                }
                .environment(\.startRecordingWithItinerary, startRecordingWithItinerary)
                .fullScreenCover(isPresented: $itineraryCreation.isPresented) {
                    ItineraryCreationView(
                        makeEditorStore: { [itineraryCreation] sport, id in
                            makeItineraryEditorStore(sport, id, itineraryCreation.source)
                        },
                        makeSaveStore: makeItinerarySaveStore,
                        onClose: { itineraryCreation.isPresented = false }
                    )
                }
                .toast($itineraryCreation.toast)
                .toast($itineraryChangeToast)
                .task {
                    for await refusal in itinerarySynchronizer.changeRefusals() {
                        itineraryChangeToast = ItineraryMessages.refused(refusal)
                    }
                }
            }
        }
        // The full screen even while the root is a bare `ProgressView`, so the splash covers it.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if isSplashPresented {
                SplashView(isSessionKnown: authStore.state != .checkingSession) {
                    isSplashPresented = false
                }
            }
        }
        .task { await authStore.restoreSession() }
        // Realtime only while signed in and in the foreground (ADR-001, ADR-010).
        .task(id: realtimeUserId) {
            if let userId = realtimeUserId {
                await realtimeService.connect(userId: userId)
            } else {
                await realtimeService.disconnect()
            }
        }
        // ADR-030 §8: full Itinerary resync on sign-in and each return to the foreground,
        // then whenever the network comes back while the app is in use. Each one first sends
        // the queued renames and deletes.
        .task(id: realtimeUserId) {
            guard realtimeUserId != nil else { return }
            try? await itinerarySynchronizer.refresh()
            await itinerarySynchronizer.resyncOnReconnection(connectivityChanges())
        }
        // ADR-031 §14: the queue is sent and the Activities in `processing` checked on sign-in and
        // each return to the foreground, then on network back and realtime (re)connections and
        // events. The default visibility is reloaded at the same moments (§13).
        .task(id: realtimeUserId) {
            guard realtimeUserId != nil else { return }
            await defaultVisibility.refresh()
            await syncCoordinator.appBecameActive()
            await syncCoordinator.observe(
                connectivity: connectivityChanges(),
                connections: realtimeService.connections(),
                events: realtimeService.events()
            )
        }
        // ADR-033 §8: an edit made elsewhere, or the official values recomputed after a sport
        // change, reach the feed's card.
        .task(id: realtimeUserId) {
            guard realtimeUserId != nil else { return }
            await reloadUpdatedActivities.run()
        }
        // ADR-030 §9: what another device saves or deletes shows here live.
        .task(id: realtimeUserId) {
            guard realtimeUserId != nil else { return }
            await itinerarySynchronizer.applyRemoteChanges()
        }
    }

    /// The Onboarding's last screen (ADR-035 §1): the account screen in creation mode, which
    /// names the account "Prénom Nom" if the code creates it.
    private func createAccountScreen(name: String, back: @escaping () -> Void) -> AccountView {
        AccountView(mode: .createAccount, authStore: authStore, name: name, onBack: back)
    }

    /// The signed-in account, for the Profile tab and its Réglages (ADR-007 rule 5: Profile does
    /// not read the Auth feature's store).
    private var profileAccount: ProfileAccount? {
        guard case .signedIn(let user) = authStore.state else { return nil }
        return ProfileAccount(id: user.id, name: user.name, email: user.email)
    }

    /// The screens a tab's stack pushes (ADR-036 §10); another athlete's profile pushes its own
    /// destinations in the same stack, `path`.
    private func appDestinations(path: Binding<NavigationPath>) -> AppDestinations {
        AppDestinations(
            activity: { AnyView(activityDetail($0)) },
            engagement: { AnyView(activityEngagement($0)) },
            athleteProfile: { AnyView(athleteProfile($0, path: path)) },
            statistics: { AnyView(athleteStatistics($0)) },
            follows: { AnyView(followLists($0)) }
        )
    }

    /// The Activity detail, pushed in the feed's and the profile's stacks (ADR-036 §10).
    private func activityDetail(_ request: ActivityDetailRequest) -> ActivityDetailPage {
        ActivityDetailPage(request: request, makeStore: makeActivityDetailStore, liveEvents: activityLiveEvents)
    }

    /// The Kudos and comments screen, pushed in the feed's and the profile's stacks (ADR-036 §8).
    private func activityEngagement(_ request: ActivityEngagementRequest) -> ActivityEngagementPage {
        ActivityEngagementPage(request: request, makeStore: makeActivityEngagementStore, liveEvents: activityLiveEvents)
    }

    /// Another athlete's profile, pushed in the stack of the tab it was opened from (ADR-036 §10).
    private func athleteProfile(_ request: AthleteProfileRequest, path: Binding<NavigationPath>) -> AthleteProfilePage {
        AthleteProfilePage(
            request: request,
            makeStore: makeAthleteProfileStore,
            openActivity: { path.wrappedValue.append($0) },
            openEngagement: { path.wrappedValue.append($0) },
            openStatistics: { profile in
                path.wrappedValue.append(AthleteStatisticsRequest(athleteId: profile.athlete.id, sports: profile.practicedSports))
            },
            openFollows: { path.wrappedValue.append($0) }
        )
    }

    /// Followers and following lists (ADR-036 §1), pushed from a profile's counters in the
    /// stack of that profile's tab.
    private func followLists(_ request: AthleteFollowsRequest) -> FollowListPage {
        FollowListPage(request: request, makeStore: makeFollowListStore)
    }

    /// A tap on an athlete in a tab's stack (ADR-036 §10): their profile pushed in that stack,
    /// or the Profile tab, at its top, for the viewer themself.
    private func openAthlete(in path: Binding<NavigationPath>) -> OpenAthleteAction {
        OpenAthleteAction { [authStore, profileStore] id in
            let viewerId: String? = if case .signedIn(let user) = authStore.state { user.id } else { nil }
            switch AthleteProfileRequest.destination(of: id, viewerId: viewerId) {
            case .ownProfile:
                profileStore.path = NavigationPath()
                selectedTab = .profile
            case .push(let request):
                path.wrappedValue.append(request)
            }
        }
    }

    /// Statistiques (ADR-036 §4), pushed from my Plus tab, and from another athlete's for the
    /// stacks that show other profiles.
    private func athleteStatistics(_ request: AthleteStatisticsRequest) -> AthleteStatisticsView {
        AthleteStatisticsView(store: makeAthleteStatisticsStore(request))
    }

    /// After Save (ADR-031 §11): the Home tab at the top of the feed, and the Activity leaves
    /// at once.
    private func activitySaved() {
        selectedTab = .feed
        Task { await feedStore.showTop() }
        Task { await syncCoordinator.activitySaved() }
    }

    /// Debug builds only: the splash and celebration preview, reached from the Profile tab.
    static var animationsPreview: AnyView? {
        #if DEBUG
        AnyView(AnimationsPreviewView())
        #else
        nil
        #endif
    }
}

/// Tabs of the signed-in app; Save brings the athlete back to the feed (ADR-031 §11).
enum AppTab: Hashable {
    case feed, map, record, profile
}
