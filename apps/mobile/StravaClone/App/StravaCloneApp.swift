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
            RootView(authStore: di.makeAuthStore(), recordingStore: di.makeRecordingStore())
                .tint(Theme.accent)
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

    var body: some View {
        Group {
            switch authStore.state {
            case .checkingSession:
                ProgressView()
            case .signedOut:
                AuthFlowView(store: authStore)
            case .signedIn:
                TabView {
                    FeedView()
                        .tabItem { Label("Fil", systemImage: "house") }
                    RecordingView(store: recordingStore)
                        .tabItem { Label("Enregistrer", systemImage: "record.circle") }
                    SegmentsView()
                        .tabItem { Label("Segments", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                    ProfileView()
                        .tabItem { Label("Profil", systemImage: "person") }
                    AuthView(store: authStore)
                        .tabItem { Label("Compte", systemImage: "person.badge.key") }
                }
            }
        }
        .task { await authStore.restoreSession() }
    }
}
