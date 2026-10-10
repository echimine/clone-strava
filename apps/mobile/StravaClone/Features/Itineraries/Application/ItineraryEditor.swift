import Foundation
import Observation

/// Runs the Itinerary editor over time (ADR-030 §2): applies gestures to the draft, sends
/// the routing requests they need, cancels requests overtaken by a newer one, and applies
/// answers back to the draft. Routing failures never block editing: pending Legs are
/// requested again when the network comes back, or after a backoff when saturated.
@Observable
@MainActor
final class ItineraryEditor {
    /// Routing outcome worth telling the athlete about.
    enum Notice: Equatable, Sendable {
        /// A Leg found no path and fell back to a straight line.
        case noPath
        /// Routing failed for now; the Leg is pending.
        case routingUnavailable
        /// The routing quota is used up (`429`); the Leg is pending.
        case routingSaturated
        /// The draft has `ItineraryDraft.maxWaypoints`: the Waypoint was not added.
        case waypointLimitReached

        init(_ error: RoutingError) {
            switch error {
            case .noPath: self = .noPath
            case .temporary: self = .routingUnavailable
            case .rateLimited: self = .routingSaturated
            }
        }
    }

    /// A Waypoint under the finger, from touch down to release.
    private struct Drag {
        let waypointID: WaypointID
        /// The draft before the gesture, recorded for undo on release.
        let origin: ItineraryDraft
        /// Whether the gesture changed the draft so far: moved, or inserted the Waypoint.
        var hasChanged = false
        /// The Waypoint was inserted by pulling a Leg, rather than an existing one moved.
        var isInsertion = false
        /// Request sent at the last pause, kept while the finger has not moved since.
        var pause: (token: UUID, request: LegRoutingRequest)?
        /// Answer to that request: previewed during the drag, applied on release.
        var pauseOutcome: Result<RoutedPath, RoutingError>?
    }

    private(set) var draft: ItineraryDraft {
        didSet { updateElevation() }
    }
    private(set) var notice: Notice?
    /// What the athlete did and what the router answered since the editor opened (issue #20).
    @ObservationIgnored private(set) var counters = ItineraryEditorCounters()
    /// Called on the first `429` of the session.
    @ObservationIgnored var onFirstRateLimit: (@MainActor () -> Void)?
    private var drag: Drag? {
        didSet { updateElevation() }
    }
    /// Elevation gain of the full track, measured by the API once a gesture is over (ADR-030 §3).
    let elevation: ItineraryElevationPreview
    /// Drafts before each gesture, most recent last. Being values, they are restored as is.
    private var undoStack: [ItineraryDraft] = []
    /// The draft the editor opened on.
    @ObservationIgnored private let initialDraft: ItineraryDraft
    private var redoStack: [ItineraryDraft] = []

    @ObservationIgnored private let router: any ItineraryRouter
    @ObservationIgnored private let pauseDelay: Duration
    @ObservationIgnored private var inFlight: [UUID: (request: LegRoutingRequest, task: Task<Void, Never>)] = [:]
    @ObservationIgnored private var pauseTask: Task<Void, Never>?
    @ObservationIgnored private let backoff: RetryBackoff
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    /// Retries already delayed by the backoff since the last routing success.
    @ObservationIgnored private var backoffAttempt = 0
    /// Waiting out the backoff before retrying the pending Legs.
    private var backoffTask: Task<Void, Never>?

    /// - Parameters:
    ///   - metricsPreviewer: measures the elevation gain; `nil` leaves it idle.
    ///   - pauseDelay: how long a dragged Waypoint must rest before its Legs are requested.
    ///   - backoff: delays between retries while routing is saturated (`429`).
    ///   - sleep: waits out a backoff delay; replaced in tests.
    init(
        sport: ItinerarySport,
        router: any ItineraryRouter,
        metricsPreviewer: (any ItineraryMetricsPreviewer)? = nil,
        pauseDelay: Duration = .milliseconds(300),
        backoff: RetryBackoff = RetryBackoff(),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        draft = ItineraryDraft(sport: sport)
        initialDraft = ItineraryDraft(sport: sport)
        elevation = ItineraryElevationPreview(previewer: metricsPreviewer)
        self.router = router
        self.pauseDelay = pauseDelay
        self.backoff = backoff
        self.sleep = sleep
    }

    /// "Modifier": the editor reopens on a saved Itinerary's draft as is, with nothing to route
    /// (ADR-030 §5) and no undo history. Only its gain is measured again.
    init(
        restoring draft: ItineraryDraft,
        router: any ItineraryRouter,
        metricsPreviewer: (any ItineraryMetricsPreviewer)? = nil,
        pauseDelay: Duration = .milliseconds(300),
        backoff: RetryBackoff = RetryBackoff(),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.draft = draft
        initialDraft = draft
        elevation = ItineraryElevationPreview(previewer: metricsPreviewer)
        self.router = router
        self.pauseDelay = pauseDelay
        self.backoff = backoff
        self.sleep = sleep
        updateElevation()
    }

    /// Waypoint under the finger, if any.
    var draggedWaypointID: WaypointID? {
        drag?.waypointID
    }

    /// The draft as drawn: during a drag that rests, the Legs follow the path found for the
    /// pause, up to the snapped position, while the Waypoint stays under the finger in `draft`.
    var displayedDraft: ItineraryDraft {
        guard let pause = drag?.pause, case .success(let path)? = drag?.pauseOutcome else { return draft }
        var preview = draft
        _ = preview.apply(path, to: pause.request)
        return preview
    }

    /// The draft differs from the one the editor opened on.
    var hasChanges: Bool {
        draft != initialDraft
    }

    var canUndo: Bool {
        drag == nil && !undoStack.isEmpty
    }

    var canRedo: Bool {
        drag == nil && !redoStack.isEmpty
    }

    /// A Leg waits for routing to be available again: "Enregistrer" waits too.
    var hasPendingLegs: Bool {
        draft.hasPendingLegs
    }

    /// Pending Legs can be requested now; while saturated, the backoff retries them by itself.
    var canRetryPendingLegs: Bool {
        hasPendingLegs && backoffTask == nil
    }

    // MARK: Gestures

    /// Tap on the map: start, then each next Waypoint at the end, up to the cap.
    func addWaypoint(at coordinate: Coordinate) {
        guard !refuseIfFull() else { return }
        if perform({ $0.appendWaypoint(at: coordinate) }) {
            counters.waypointsAdded += 1
        }
    }

    /// Bubble on a Leg: straight line, or back to following roads and trails.
    func setMode(_ mode: LegMode, ofLeg id: LegID) {
        if perform({ $0.setMode(mode, ofLeg: id) }), mode == .straight {
            counters.legsSwitchedToStraight += 1
        }
    }

    /// "Supprimer" in a Waypoint's bubble: its neighbors are joined by a new Leg.
    func removeWaypoint(_ id: WaypointID) {
        perform { $0.removeWaypoint(id) }
    }

    /// Another sport picked in the stats card. In another category (foot ↔ wheels), the
    /// `follow` Legs are requested again in parallel batches while editing goes on; the
    /// change is one undo entry, restoring the sport and the Legs of before.
    func changeSport(to sport: ItinerarySport) {
        performAll { $0.changeSport(to: sport) }
    }

    /// The finger lands on a Waypoint.
    func beginDrag(_ id: WaypointID) {
        guard drag == nil, draft.waypoints.contains(where: { $0.id == id }) else { return }
        drag = Drag(waypointID: id, origin: draft)
    }

    /// The finger pulls a Leg: a Waypoint is inserted there and dragged from now on.
    func beginInsertion(intoLeg id: LegID, at coordinate: Coordinate) {
        guard drag == nil, !refuseIfFull() else { return }
        var inserted = draft
        guard let waypointID = inserted.insertWaypoint(intoLeg: id, at: coordinate) else { return }
        // The drag starts before the draft changes: the new track is never measured mid-gesture.
        drag = Drag(waypointID: waypointID, origin: draft, hasChanged: true, isInsertion: true)
        draft = inserted
        restartPauseTimer()
    }

    /// The finger moves: the Waypoint follows it, and its Legs are requested once it rests
    /// for `pauseDelay`. A request sent at an earlier pause is overtaken and cancelled.
    func drag(to coordinate: Coordinate) {
        guard var current = drag else { return }
        let before = draft
        draft.moveWaypoint(current.waypointID, to: coordinate)
        guard draft != before else { return }
        if let pause = current.pause {
            inFlight[pause.token]?.task.cancel()
        }
        current.hasChanged = true
        current.pause = nil
        current.pauseOutcome = nil
        drag = current
        restartPauseTimer()
    }

    /// The finger lifts. Released where it rested, the pause answer is applied (or will be
    /// when it arrives); otherwise the Legs are requested now.
    func endDrag() {
        guard let ended = drag else { return }
        pauseTask?.cancel()
        drag = nil
        guard ended.hasChanged else { return }
        if ended.isInsertion {
            counters.waypointsInserted += 1
        } else {
            counters.waypointsMoved += 1
        }
        record(ended.origin)
        if let pause = ended.pause {
            if let outcome = ended.pauseOutcome {
                resolve(pause.request, with: outcome)
            }
        } else if let request = draft.routeLegs(around: ended.waypointID) {
            send(request)
        }
        requestStrandedLegs()
    }

    /// Back to the draft before the last gesture. Legs it left computing are requested again
    /// unless their request is still in flight.
    func undo() {
        guard drag == nil, let previous = undoStack.popLast() else { return }
        counters.undos += 1
        redoStack.append(draft)
        restore(previous)
    }

    /// Forward to the draft the last undo left.
    func redo() {
        guard drag == nil, let next = redoStack.popLast() else { return }
        counters.redos += 1
        undoStack.append(draft)
        restore(next)
    }

    func dismissNotice() {
        notice = nil
    }

    // MARK: Resilience

    /// Requests the pending Legs again, unless the backoff is about to.
    func retryPendingLegs() {
        guard backoffTask == nil else { return }
        draft.retryPendingLegs().forEach { send($0) }
    }

    /// Runs for as long as `connectivity` does (`true` when connected): the pending Legs are
    /// requested again each time the network comes back. The first value is the current
    /// state, not a change.
    func retryPendingLegs(onReconnectionOf connectivity: AsyncStream<Bool>) async {
        var wasConnected: Bool?
        for await isConnected in connectivity {
            defer { wasConnected = isConnected }
            guard isConnected, wasConnected == false else { continue }
            retryPendingLegs()
        }
    }

    /// Waits until every routing request in flight, follow-ups included, has been answered,
    /// then the elevation preview they led to.
    func settle() async {
        while let task = inFlight.values.first?.task {
            await task.value
        }
        await elevation.settle()
    }

    // MARK: History

    /// At the cap, a new Waypoint is refused with a notice.
    private func refuseIfFull() -> Bool {
        guard draft.isFull else { return false }
        notice = .waypointLimitReached
        return true
    }

    /// Applies a one-shot gesture; it becomes an undo entry only if it changed the draft.
    /// - Returns: whether it changed the draft.
    @discardableResult
    private func perform(_ gesture: (inout ItineraryDraft) -> LegRoutingRequest?) -> Bool {
        performAll { draft in gesture(&draft).map { [$0] } ?? [] }
    }

    @discardableResult
    private func performAll(_ gesture: (inout ItineraryDraft) -> [LegRoutingRequest]) -> Bool {
        guard drag == nil else { return false }
        let before = draft
        let requests = gesture(&draft)
        guard draft != before else { return false }
        record(before)
        requests.forEach { send($0) }
        requestStrandedLegs()
        return true
    }

    private func record(_ previous: ItineraryDraft) {
        undoStack.append(previous)
        redoStack.removeAll()
    }

    private func restore(_ state: ItineraryDraft) {
        draft = state
        requestStrandedLegs()
    }

    // MARK: Elevation

    /// The gain is measured on release only: a gesture that changed the draft keeps it greyed out.
    private func updateElevation() {
        if let drag, draft != drag.origin {
            elevation.update(.changing)
        } else if let request = draft.geometry {
            elevation.update(.settled(request))
        } else {
            elevation.update(draft.waypoints.count < 2 ? .empty : .changing)
        }
    }

    // MARK: Routing

    private func restartPauseTimer() {
        pauseTask?.cancel()
        pauseTask = Task { [pauseDelay] in
            try? await Task.sleep(for: pauseDelay)
            guard !Task.isCancelled else { return }
            self.dragDidPause()
        }
    }

    private func dragDidPause() {
        guard var current = drag, current.pause == nil,
              let request = draft.routeLegs(around: current.waypointID) else { return }
        current.pause = (send(request), request)
        drag = current
        requestStrandedLegs()
    }

    @discardableResult
    private func send(_ request: LegRoutingRequest) -> UUID {
        let legIDs = request.legIDs
        for (token, entry) in inFlight where !entry.request.legIDs.isDisjoint(with: legIDs) {
            entry.task.cancel()
            inFlight[token] = nil
        }
        let token = UUID()
        counters.directionsRequests += 1
        let router = router
        let task = Task {
            let outcome: Result<RoutedPath, RoutingError>?
            do {
                outcome = .success(try await router.path(through: request.waypoints, profile: request.profile))
            } catch let error as RoutingError {
                outcome = .failure(error)
            } catch {
                outcome = Task.isCancelled ? nil : .failure(.temporary)
            }
            self.finish(token, request: request, outcome: outcome)
        }
        inFlight[token] = (request, task)
        return token
    }

    private func finish(_ token: UUID, request: LegRoutingRequest, outcome: Result<RoutedPath, RoutingError>?) {
        inFlight[token] = nil
        if case .failure(let error)? = outcome {
            count(error)
        }
        guard let outcome, !Task.isCancelled else { return }
        if var current = drag, current.pause?.token == token {
            current.pauseOutcome = outcome
            drag = current
            return
        }
        resolve(request, with: outcome)
    }

    private func resolve(_ request: LegRoutingRequest, with outcome: Result<RoutedPath, RoutingError>) {
        let resolution = switch outcome {
        case .success(let path): draft.apply(path, to: request)
        case .failure(let error): draft.fail(error, for: request)
        }
        defer { requestStrandedLegs() }
        guard case .applied(let followUps) = resolution else { return }
        switch outcome {
        case .success:
            backoffAttempt = 0
            if notice == .routingUnavailable || notice == .routingSaturated, !draft.hasPendingLegs {
                notice = nil
            }
        case .failure(let error):
            // Several Legs with no path are requested again one by one: none went straight yet.
            if error != .noPath || followUps.isEmpty {
                notice = Notice(error)
            }
            if error == .rateLimited {
                scheduleBackoff()
            }
        }
        followUps.forEach { send($0) }
    }

    private func count(_ error: RoutingError) {
        switch error {
        case .noPath: counters.noPathResponses += 1
        case .temporary: counters.networkFailures += 1
        case .rateLimited:
            counters.rateLimitedResponses += 1
            if counters.rateLimitedResponses == 1 {
                onFirstRateLimit?()
            }
        }
    }

    /// Legs left computing with no request in flight, e.g. once a gesture overtook their
    /// batch, are requested again; those around the dragged Waypoint wait for its pause.
    private func requestStrandedLegs() {
        let awaited = inFlight.values.map(\.request).filter(draft.isCurrent)
        var excluded = Set<LegID>()
        if let drag, let index = draft.waypoints.firstIndex(where: { $0.id == drag.waypointID }) {
            excluded = Set([index - 1, index].filter(draft.legs.indices.contains).map { draft.legs[$0].id })
        }
        draft.requestsForStrandedLegs(awaited: awaited, excluding: excluded).forEach { send($0) }
    }

    /// Saturated: the pending Legs are retried after a delay doubled at each new `429`.
    /// Several `429`s answered together wait for the same retry.
    private func scheduleBackoff() {
        guard backoffTask == nil else { return }
        let delay = backoff.delay(beforeRetry: backoffAttempt)
        backoffAttempt += 1
        let sleep = sleep
        backoffTask = Task { [weak self] in
            do {
                try await sleep(delay)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.backoffTask = nil
            self.retryPendingLegs()
        }
    }
}
