import Foundation
import Observation

/// Runs the Itinerary editor over time (ADR-030 §2): applies gestures to the draft, sends
/// the routing requests they need, cancels requests overtaken by a newer one, and applies
/// answers back to the draft.
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
        /// Request sent at the last pause, kept while the finger has not moved since.
        var pause: (token: UUID, request: LegRoutingRequest)?
        /// Answer to that request: previewed during the drag, applied on release.
        var pauseOutcome: Result<RoutedPath, RoutingError>?
    }

    private(set) var draft: ItineraryDraft
    private(set) var notice: Notice?
    private var drag: Drag?
    /// Drafts before each gesture, most recent last. Being values, they are restored as is.
    private var undoStack: [ItineraryDraft] = []
    private var redoStack: [ItineraryDraft] = []

    @ObservationIgnored private let router: any ItineraryRouter
    @ObservationIgnored private let pauseDelay: Duration
    @ObservationIgnored private var inFlight: [UUID: (request: LegRoutingRequest, task: Task<Void, Never>)] = [:]
    @ObservationIgnored private var pauseTask: Task<Void, Never>?

    /// - Parameter pauseDelay: how long a dragged Waypoint must rest before its Legs are requested.
    init(sport: ItinerarySport, router: any ItineraryRouter, pauseDelay: Duration = .milliseconds(300)) {
        draft = ItineraryDraft(sport: sport)
        self.router = router
        self.pauseDelay = pauseDelay
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

    var canUndo: Bool {
        drag == nil && !undoStack.isEmpty
    }

    var canRedo: Bool {
        drag == nil && !redoStack.isEmpty
    }

    // MARK: Gestures

    /// Tap on the map: start, then each next Waypoint at the end.
    func addWaypoint(at coordinate: Coordinate) {
        perform { $0.appendWaypoint(at: coordinate) }
    }

    /// Bubble on a Leg: straight line, or back to following roads and trails.
    func setMode(_ mode: LegMode, ofLeg id: LegID) {
        perform { $0.setMode(mode, ofLeg: id) }
    }

    /// "Supprimer" in a Waypoint's bubble: its neighbors are joined by a new Leg.
    func removeWaypoint(_ id: WaypointID) {
        perform { $0.removeWaypoint(id) }
    }

    /// The finger lands on a Waypoint.
    func beginDrag(_ id: WaypointID) {
        guard drag == nil, draft.waypoints.contains(where: { $0.id == id }) else { return }
        drag = Drag(waypointID: id, origin: draft)
    }

    /// The finger pulls a Leg: a Waypoint is inserted there and dragged from now on.
    func beginInsertion(intoLeg id: LegID, at coordinate: Coordinate) {
        guard drag == nil else { return }
        let origin = draft
        guard let waypointID = draft.insertWaypoint(intoLeg: id, at: coordinate) else { return }
        drag = Drag(waypointID: waypointID, origin: origin, hasChanged: true)
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
        record(ended.origin)
        if let pause = ended.pause {
            if let outcome = ended.pauseOutcome {
                resolve(pause.request, with: outcome)
            }
        } else if let request = draft.routeLegs(around: ended.waypointID) {
            send(request)
        }
    }

    /// Back to the draft before the last gesture. Legs it left computing are requested again
    /// unless their request is still in flight.
    func undo() {
        guard drag == nil, let previous = undoStack.popLast() else { return }
        redoStack.append(draft)
        restore(previous)
    }

    /// Forward to the draft the last undo left.
    func redo() {
        guard drag == nil, let next = redoStack.popLast() else { return }
        undoStack.append(draft)
        restore(next)
    }

    func dismissNotice() {
        notice = nil
    }

    /// Waits until every routing request in flight, follow-ups included, has been answered.
    func settle() async {
        while let task = inFlight.values.first?.task {
            await task.value
        }
    }

    // MARK: History

    /// Applies a one-shot gesture; it becomes an undo entry only if it changed the draft.
    private func perform(_ gesture: (inout ItineraryDraft) -> LegRoutingRequest?) {
        guard drag == nil else { return }
        let before = draft
        let request = gesture(&draft)
        guard draft != before else { return }
        record(before)
        if let request {
            send(request)
        }
    }

    private func record(_ previous: ItineraryDraft) {
        undoStack.append(previous)
        redoStack.removeAll()
    }

    private func restore(_ state: ItineraryDraft) {
        draft = state
        let awaited = inFlight.values.map(\.request).filter(draft.isCurrent)
        for request in draft.requestsForComputingLegs()
        where !awaited.contains(where: { !$0.legIDs.isDisjoint(with: request.legIDs) }) {
            send(request)
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
    }

    @discardableResult
    private func send(_ request: LegRoutingRequest) -> UUID {
        let legIDs = request.legIDs
        for entry in inFlight.values where !entry.request.legIDs.isDisjoint(with: legIDs) {
            entry.task.cancel()
        }
        let token = UUID()
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
        guard case .applied(let followUps) = resolution else { return }
        if case .failure(let error) = outcome {
            notice = Notice(error)
        }
        followUps.forEach { send($0) }
    }
}
