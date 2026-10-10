import Foundation

/// Values injected at build time through Config/*.xcconfig and Info.plist.
struct AppConfiguration: Sendable {
    let apiBaseURL: URL
    let realtimeURL: URL
    let mapboxAccessToken: String
    /// Mapbox Directions token dedicated to Itineraries (ADR-030 §2), never the map's token.
    let mapboxItinerariesToken: String
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
        mapboxItinerariesToken = value("MapboxItinerariesToken")
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
    /// Single GPS source shared by the map puck and Recording (ADR-027).
    let locationProvider: CoreLocationProvider
    let locationPermission: LocationPermissionService

    /// Shared realtime connection (ADR-010), opened while signed in and in the foreground.
    let realtimeService: RealtimeService
    /// Avatars and static maps (ADR-029), one cache for the whole app.
    let imageLoader = ImageLoader.shared
    /// Full resync of the Itinerary cache and its queue of changes (ADR-030 §8), triggered by
    /// the app shell.
    let itinerarySynchronizer: ItinerarySynchronizer
    /// Product events (ADR-015): PostHog, opted out until a consent screen exists; nothing
    /// without a key.
    let analytics: any AnalyticsClient

    private let recordingService: RecordingService
    private let authService: AuthService
    private let importRepository: APIActivityImportRepository
    private let feedRepository: APIFeedRepository
    private let itineraryRouter: MapboxDirectionsRouter
    private let itineraryRepository: APIItineraryRepository
    private let itineraryCache: GRDBItineraryCache

    init(configuration: AppConfiguration = AppConfiguration(), database: AppDatabase) {
        self.configuration = configuration
        self.database = database
        authSession = AuthSession()
        apiClient = APIClient(baseURL: configuration.apiBaseURL, authSession: authSession)
        webSocketClient = WebSocketClient(url: configuration.realtimeURL)
        connectivityMonitor = ConnectivityMonitor()
        locationProvider = CoreLocationProvider()
        locationPermission = LocationPermissionService()

        // TODO(ADR-014): configure RevenueCat behind a SubscriptionService port (Features/Paywall).
        analytics = PostHogAnalyticsClient.make(projectToken: configuration.postHogAPIKey) ?? NoAnalyticsClient()
        // TODO(ADR-022): Apple Sign-In — blocked on a paid Apple Developer Program membership.
        // TODO(ADR-022 §5): admin 2FA — credential-only, backoffice web, not applicable to mobile.

        recordingService = RecordingService(
            locationProvider: locationProvider,
            repository: GRDBRecordingRepository(database: database)
        )
        realtimeService = RealtimeService(
            client: webSocketClient,
            tokenProvider: RealtimeTokenProvider(apiClient: apiClient)
        )
        importRepository = APIActivityImportRepository(apiClient: apiClient)
        feedRepository = APIFeedRepository(apiClient: apiClient)
        itineraryRouter = MapboxDirectionsRouter(accessToken: configuration.mapboxItinerariesToken)
        itineraryRepository = APIItineraryRepository(apiClient: apiClient)
        itineraryCache = GRDBItineraryCache(database: database)
        itinerarySynchronizer = ItinerarySynchronizer(
            repository: itineraryRepository,
            cache: itineraryCache,
            changes: ItineraryChangeSender(
                repository: itineraryRepository,
                cache: itineraryCache,
                queue: GRDBItineraryChangeQueue(database: database),
                sessionRefresher: APISessionRefresher(apiClient: apiClient, authSession: authSession)
            ),
            events: RealtimeItineraryEventSource(client: webSocketClient)
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

    func makeFeedStore() -> FeedStore {
        FeedStore(
            loadFeed: LoadFeed(repository: feedRepository),
            toggleKudos: ToggleKudos(repository: feedRepository),
            events: RealtimeFeedEventSource(client: webSocketClient)
        )
    }

    /// - Parameter id: the new Itinerary's, generated by its save store: links the events.
    func makeItineraryEditorStore(
        sport: ItinerarySport,
        id: ItineraryID,
        source: AnalyticsEvent.EditorSource
    ) -> ItineraryEditorStore {
        ItineraryEditorStore(
            editor: ItineraryEditor(
                sport: sport,
                router: itineraryRouter,
                metricsPreviewer: APIItineraryMetricsPreviewer(apiClient: apiClient)
            ),
            connectivityChanges: connectivityChanges,
            tracking: ItineraryEditorTracking(analytics: analytics, itineraryID: id, mode: .create, source: source)
        )
    }

    func makeItinerarySaveStore() -> ItinerarySaveStore {
        ItinerarySaveStore(save: SaveItinerary(repository: itineraryRepository, cache: itineraryCache))
    }

    func makeItineraryListStore(source: AnalyticsEvent.ListSource = .profile) -> ItineraryListStore {
        ItineraryListStore(cache: itineraryCache, synchronizer: itinerarySynchronizer, source: source, analytics: analytics)
    }

    /// The Map tab sheet has its own list (own page size), over the same cache.
    func makeMapItinerariesStore() -> MapItinerariesStore {
        MapItinerariesStore(
            list: makeItineraryListStore(source: .mapTab),
            makeDetailStore: { [self] id in makeItineraryDetailStore(id: id, source: .mapTab) }
        )
    }

    func makeItineraryDetailStore(id: ItineraryID, source: AnalyticsEvent.ListSource) -> ItineraryDetailStore {
        let connectivityMonitor = connectivityMonitor
        return ItineraryDetailStore(
            id: id,
            cache: itineraryCache,
            synchronizer: itinerarySynchronizer,
            source: source,
            analytics: analytics,
            isOnline: { connectivityMonitor.status.isConnected }
        )
    }

    /// "Modifier" on a detail (ADR-030 §5): the editor reopens on the stored Waypoints and Legs.
    func makeItineraryEditFlow(id: ItineraryID) -> ItineraryEditFlow {
        let connectivityMonitor = connectivityMonitor
        return ItineraryEditFlow(
            id: id,
            isOnline: { connectivityMonitor.status.isConnected },
            load: LoadSavedItinerary(repository: itineraryRepository, cache: itineraryCache),
            makeEditorStore: { [self] draft in
                ItineraryEditorStore(
                    editor: ItineraryEditor(
                        restoring: draft,
                        router: itineraryRouter,
                        metricsPreviewer: APIItineraryMetricsPreviewer(apiClient: apiClient)
                    ),
                    connectivityChanges: connectivityChanges,
                    tracking: ItineraryEditorTracking(analytics: analytics, itineraryID: id, mode: .edit, source: .detail)
                )
            },
            makeSaveStore: { [self] saved in
                ItinerarySaveStore(update: UpdateItinerary(repository: itineraryRepository, cache: itineraryCache), itinerary: saved)
            },
            analytics: analytics
        )
    }

    func makeItineraryCreationFlow() -> ItineraryCreationFlow {
        let connectivityMonitor = connectivityMonitor
        return ItineraryCreationFlow(isOnline: { connectivityMonitor.status.isConnected }, analytics: analytics)
    }

    /// `true` while a network route exists, current state first (`ConnectivityMonitor`).
    func connectivityChanges() -> AsyncStream<Bool> {
        let updates = connectivityMonitor.updates()
        return AsyncStream { continuation in
            let task = Task {
                for await status in updates {
                    continuation.yield(status.isConnected)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func makeImportStore() -> ImportStore {
        ImportStore(
            prepareFile: PrepareImportFile(staging: TemporaryImportFileStager()),
            importFile: ImportActivityFile(repository: importRepository),
            tracker: ImportTracker(
                repository: importRepository,
                events: RealtimeImportEventSource(client: webSocketClient)
            )
        )
    }
}
