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
                recordingStore: di.makeRecordingStore(),
                importStore: di.makeImportStore(),
                feedStore: di.makeFeedStore(),
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
                defaultVisibility: di.defaultVisibility
            )
                .tint(Theme.accent)
                .environment(\.imageLoader, di.imageLoader)
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

/// Gates the app behind the auth flow (ADR-022): the TabView is only reachable once
/// signed in. Session is checked once at launch (`AuthStore.restoreSession`).
struct RootView: View {
    @State var authStore: AuthStore
    @State var recordingStore: RecordingStore
    @State var importStore: ImportStore
    @State var feedStore: FeedStore
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
                AuthFlowView(store: authStore)
                    .onAppear {
                        feedStore.reset()
                        defaultVisibility.clear()
                        // ADR-030 §8: the Itinerary cache does not outlive the session.
                        Task { await itinerarySynchronizer.signOut() }
                    }
            case .signedIn:
                TabView(selection: $selectedTab) {
                    FeedView(store: feedStore, onImportActivity: importStore.startImport) {
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
                    ProfileView(store: authStore, signOutWarning: {
                        // ADR-031 §10, §14: one confirmation for all that a sign-out loses.
                        SignOutWarning.message(
                            recordingInProgress: await recordingStore.signOutWarning() != nil,
                            unsentActivities: await syncCoordinator.unsentActivityCount(),
                            pendingItineraryChanges: await itinerarySynchronizer.pendingChangeCount()
                        )
                    }, beforeSignOut: {
                        await recordingStore.delete()
                        await syncCoordinator.signOut()
                    }) {
                        MyItinerariesView(
                            store: itineraryListStore,
                            makeDetailStore: makeItineraryDetailStore,
                            makeEditFlow: makeItineraryEditFlow,
                            onCreate: { itineraryCreation.start(from: .profile) }
                        )
                    }
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
        // ADR-030 §9: what another device saves or deletes shows here live.
        .task(id: realtimeUserId) {
            guard realtimeUserId != nil else { return }
            await itinerarySynchronizer.applyRemoteChanges()
        }
    }

    /// After Save (ADR-031 §11): the Home tab at the top of the feed, and the Activity leaves
    /// at once.
    private func activitySaved() {
        selectedTab = .feed
        Task { await feedStore.showTop() }
        Task { await syncCoordinator.activitySaved() }
    }
}

/// Tabs of the signed-in app; Save brings the athlete back to the feed (ADR-031 §11).
enum AppTab: Hashable {
    case feed, map, record, profile
}
