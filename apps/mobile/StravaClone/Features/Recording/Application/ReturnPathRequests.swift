import Foundation

/// The work behind the Return path of a Recording (ADR-031 §7): the router call in flight, the
/// retry timer and the network state. It holds no Recording state: what happens is handed to
/// its owner as an `Event`, and the rules (`FollowedItinerary`) decide what to do next. Owned
/// by `RecordingService` and only used from its actor.
struct ReturnPathRequests {
    enum Event: Sendable {
        case arrived(RoutedReturnPath, for: ReturnPathRequest)
        case failed(RoutingError, for: ReturnPathRequest)
        /// A wanted request may leave now, without waiting for a new fix.
        case retryDue
        /// `true` while a network route exists; the current state comes first.
        case connectivity(Bool)
    }

    typealias Handler = @Sendable (Event) async -> Void

    private let router: (any ReturnPathRouter)?
    private let connectivity: (@Sendable () async -> AsyncStream<Bool>)?
    private let sleep: @Sendable (Duration) async throws -> Void
    private var request: Task<Void, Never>?
    private var retry: (date: Date, task: Task<Void, Never>)?
    private var connectivityConsumer: Task<Void, Never>?

    init(
        router: (any ReturnPathRouter)?,
        connectivity: (@Sendable () async -> AsyncStream<Bool>)?,
        sleep: @escaping @Sendable (Duration) async throws -> Void
    ) {
        self.router = router
        self.connectivity = connectivity
        self.sleep = sleep
    }

    /// Asks the router, replacing the request in flight. Without a router, nothing leaves.
    mutating func send(_ request: ReturnPathRequest, profile: RoutingProfile, then handle: @escaping Handler) {
        guard let router else { return }
        self.request?.cancel()
        self.request = Task {
            do {
                let routed = try await router.returnPath(
                    from: request.position,
                    to: request.returnPoint.coordinate,
                    profile: profile,
                    bearing: request.bearing
                )
                await handle(.arrived(routed, for: request))
            } catch is CancellationError {
                // Back on the track, Itinerary removed or Recording over.
            } catch {
                await handle(.failed(error as? RoutingError ?? .temporary, for: request))
            }
        }
    }

    /// The request in flight is no longer wanted.
    mutating func cancelRequest() {
        request?.cancel()
        request = nil
    }

    /// One timer at `date`, the date at which a wanted request may leave; replaced when the date
    /// changes, cancelled with `nil` (nothing waits).
    mutating func scheduleRetry(at date: Date?, now: Date, then handle: @escaping Handler) {
        guard date != retry?.date else { return }
        retry?.task.cancel()
        retry = nil
        guard let date else { return }
        let delay = max(0, date.timeIntervalSince(now))
        let sleep = sleep
        let task = Task {
            guard (try? await sleep(.seconds(delay))) != nil, !Task.isCancelled else { return }
            await handle(.retryDue)
        }
        retry = (date, task)
    }

    /// The timer fired: the next date starts a new one.
    mutating func retryFired() {
        retry = nil
    }

    /// Follows the network state until `stop()`.
    mutating func observeConnectivity(then handle: @escaping Handler) {
        connectivityConsumer?.cancel()
        guard let connectivity else { return }
        connectivityConsumer = Task {
            for await isOnline in await connectivity() {
                await handle(.connectivity(isOnline))
            }
        }
    }

    /// The Recording is over (Save, Delete): nothing more leaves.
    mutating func stop() {
        cancelRequest()
        retry?.task.cancel()
        retry = nil
        connectivityConsumer?.cancel()
        connectivityConsumer = nil
    }
}
