import Foundation

/// Values injected at build time through Config/*.xcconfig and Info.plist.
struct AppConfiguration: Sendable {
    let apiBaseURL: URL
    let realtimeURL: URL
    let mapboxAccessToken: String
    let revenueCatAPIKey: String
    let postHogAPIKey: String

    init(bundle: Bundle = .main) {
        func value(_ key: String) -> String {
            (bundle.object(forInfoDictionaryKey: key) as? String) ?? ""
        }
        func url(_ key: String, fallback: String) -> URL {
            URL(string: value(key)).flatMap { $0.scheme == nil ? nil : $0 } ?? URL(string: fallback)!
        }
        apiBaseURL = url("APIBaseURL", fallback: "http://localhost:3001")
        realtimeURL = url("RealtimeURL", fallback: "ws://localhost:3003/ws")
        mapboxAccessToken = value("MBXAccessToken")
        revenueCatAPIKey = value("RevenueCatAPIKey")
        postHogAPIKey = value("PostHogAPIKey")
    }
}

/// Composition root (ADR-007): creates the shared objects, then each feature's
/// repositories, use cases, services and stores. Initializer injection only, no singletons.
@MainActor
final class Di {
    let configuration: AppConfiguration
    let database: AppDatabase
    let authSession: AuthSession
    let apiClient: APIClient
    let webSocketClient: WebSocketClient
    let connectivityMonitor: ConnectivityMonitor

    private let recordingService: RecordingService
    private let authService: AuthService

    init(configuration: AppConfiguration = AppConfiguration(), database: AppDatabase) {
        self.configuration = configuration
        self.database = database
        authSession = AuthSession()
        apiClient = APIClient(baseURL: configuration.apiBaseURL, authSession: authSession)
        webSocketClient = WebSocketClient(url: configuration.realtimeURL)
        connectivityMonitor = ConnectivityMonitor()

        // TODO(ADR-014): configure RevenueCat behind a SubscriptionService port (Features/Paywall).
        // TODO(ADR-015): configure PostHog behind an analytics port, session replay disabled.
        // TODO(ADR-022): Apple Sign-In — blocked on a paid Apple Developer Program membership.
        // TODO(ADR-022 §5): admin 2FA — credential-only, backoffice web, not applicable to mobile.

        recordingService = RecordingService(
            locationProvider: CoreLocationProvider(),
            repository: GRDBRecordingRepository(database: database)
        )
        authService = AuthService(
            repository: APIAuthRepository(apiClient: apiClient, authSession: authSession),
            googleAuthProvider: GIDGoogleAuthProvider()
        )
    }

    static func live() throws -> Di {
        try Di(database: .onDisk())
    }

    func start() {
        connectivityMonitor.start()
    }

    func makeRecordingStore() -> RecordingStore {
        RecordingStore(service: recordingService)
    }

    func makeAuthStore() -> AuthStore {
        AuthStore(service: authService)
    }
}
