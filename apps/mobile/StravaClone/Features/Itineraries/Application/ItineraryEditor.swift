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

    private(set) var draft: ItineraryDraft
    private(set) var notice: Notice?

    @ObservationIgnored private let router: any ItineraryRouter
    @ObservationIgnored private var inFlight: [UUID: (legIDs: Set<LegID>, task: Task<Void, Never>)] = [:]

    init(sport: ItinerarySport, router: any ItineraryRouter) {
        draft = ItineraryDraft(sport: sport)
        self.router = router
    }

    // MARK: Gestures

    /// Tap on the map: start, then each next Waypoint at the end.
    func addWaypoint(at coordinate: Coordinate) {
        guard let request = draft.appendWaypoint(at: coordinate) else { return }
        send(request)
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

    // MARK: Routing

    private func send(_ request: LegRoutingRequest) {
        let legIDs = request.legIDs
        for entry in inFlight.values where !entry.legIDs.isDisjoint(with: legIDs) {
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
        inFlight[token] = (legIDs, task)
    }

    private func finish(_ token: UUID, request: LegRoutingRequest, outcome: Result<RoutedPath, RoutingError>?) {
        inFlight[token] = nil
        guard let outcome, !Task.isCancelled else { return }
        let resolution = switch outcome {
        case .success(let path): draft.apply(path, to: request)
        case .failure(let error): draft.fail(error, for: request)
        }
        guard case .applied(let followUps) = resolution else { return }
        if case .failure(let error) = outcome {
            notice = Notice(error)
        }
        followUps.forEach(send)
    }
}
