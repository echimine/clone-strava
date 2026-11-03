import Foundation
import Observation

/// The follow buttons of one screen (ADR-036 §1, §10): another athlete's profile, a followers
/// or following list, the search. Each athlete's status, as the server last gave it or as just
/// tapped. Optimistic: the button changes at once, then takes the server's answer, or goes back
/// with a toast. A tap while that athlete's change is in flight is ignored.
@Observable
@MainActor
final class FollowStore {
    private(set) var statuses: [String: FollowStatus] = [:]
    /// What went wrong with the last change.
    var toast: String?

    @ObservationIgnored private let followAthlete: FollowAthlete
    @ObservationIgnored private let unfollowAthlete: UnfollowAthlete
    @ObservationIgnored private var inFlight: Set<String> = []
    @ObservationIgnored private var observers: [@MainActor (_ previous: FollowStatus, _ change: FollowChange) -> Void] = []

    init(followAthlete: FollowAthlete, unfollowAthlete: UnfollowAthlete) {
        self.followAthlete = followAthlete
        self.unfollowAthlete = unfollowAthlete
    }

    /// Told of every change the server confirmed, with the status before it: the viewer's own
    /// following counter moves with them.
    func observeChanges(_ observer: @escaping @MainActor (_ previous: FollowStatus, _ change: FollowChange) -> Void) {
        observers.append(observer)
    }

    /// Nil for the viewer (no button), or an athlete this screen has not shown.
    func status(of athleteId: String) -> FollowStatus? {
        statuses[athleteId]
    }

    /// The server's status, from a profile or a list row; nil is the viewer. Ignored while a
    /// change of that athlete is in flight.
    func track(_ athleteId: String, status: FollowStatus?) {
        guard !inFlight.contains(athleteId) else { return }
        statuses[athleteId] = status
    }

    /// "Suivre": "Abonné" at once, then the server's answer ("Demande envoyée" when the athlete
    /// approves their followers). Nil when ignored or refused.
    @discardableResult
    func follow(_ athleteId: String) async -> FollowChange? {
        await change(athleteId, to: .accepted, failure: AthletesMessages.followFailed) { [followAthlete] () async throws(AthleteError) in
            try await followAthlete(athleteId)
        }
    }

    /// "Se désabonner", or a tap on "Demande envoyée": "Suivre" at once.
    @discardableResult
    func unfollow(_ athleteId: String) async -> FollowChange? {
        let failure = statuses[athleteId] == .pending ? AthletesMessages.cancelFailed : AthletesMessages.unfollowFailed
        return await change(athleteId, to: .none, failure: failure) { [unfollowAthlete] () async throws(AthleteError) in
            try await unfollowAthlete(athleteId)
        }
    }

    private func change(
        _ athleteId: String,
        to optimistic: FollowStatus,
        failure: String,
        _ send: () async throws(AthleteError) -> FollowChange
    ) async -> FollowChange? {
        guard !inFlight.contains(athleteId), let previous = statuses[athleteId], previous != optimistic else { return nil }
        inFlight.insert(athleteId)
        defer { inFlight.remove(athleteId) }
        statuses[athleteId] = optimistic
        do {
            let change = try await send()
            statuses[athleteId] = change.status
            for observer in observers {
                observer(previous, change)
            }
            return change
        } catch {
            statuses[athleteId] = previous
            toast = error == .offline ? AthletesMessages.message(for: error) : failure
            return nil
        }
    }
}
