import GoogleSignIn
import SwiftUI

@main
struct StravaCloneApp: App {
    private let di: Di

    init() {
        // UI tests launch with `-uiTestResetAuth` to start from a clean, signed-out
        // state regardless of what a previous run left in the Keychain.
        if ProcessInfo.processInfo.arguments.contains("-uiTestResetAuth") {
            AuthSession().clear()
        }
        do {
            di = try Di.live()
        } catch {
            fatalError("Unable to open the local database: \(error)")
        }
        di.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                authStore: di.makeAuthStore(),
                recordingStore: di.makeRecordingStore(),
                importStore: di.makeImportStore(),
                feedStore: di.makeFeedStore(),
                realtimeService: di.realtimeService,
                makeItineraryEditorStore: di.makeItineraryEditorStore
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
    let makeItineraryEditorStore: @MainActor (ItinerarySport) -> ItineraryEditorStore

    @Environment(\.scenePhase) private var scenePhase
    @State private var isCreatingItinerary = false

    /// Signed-in user id while the app is in the foreground: drives the realtime connection.
    private var realtimeUserId: String? {
        guard scenePhase == .active, case .signedIn(let user) = authStore.state else { return nil }
        return user.id
    }

    var body: some View {
        Group {
            switch authStore.state {
            case .checkingSession:
                ProgressView()
            case .signedOut:
                AuthFlowView(store: authStore)
                    .onAppear { feedStore.reset() }
            case .signedIn:
                TabView {
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
                    MapScreen(onCreateItinerary: { isCreatingItinerary = true })
                        .fullScreenCover(isPresented: $isCreatingItinerary) {
                            ItineraryCreationView(
                                makeEditorStore: makeItineraryEditorStore,
                                onClose: { isCreatingItinerary = false }
                            )
                        }
                        .tabItem { Label("Map", systemImage: "map") }
                    RecordingView(store: recordingStore)
                        .tabItem { Label("Enregistrer", systemImage: "record.circle") }
                    ProfileView(store: authStore)
                        .tabItem { Label("Profil", systemImage: "person") }
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
    }
}
