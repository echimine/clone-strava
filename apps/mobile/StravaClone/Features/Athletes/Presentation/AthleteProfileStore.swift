import Foundation
import Observation

/// Another athlete's profile (ADR-036 §1, §3, §10): their header and counters, the follow
/// button, and the Activités · Plus tabs. One per pushed profile.
@Observable
@MainActor
final class AthleteProfileStore {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(message: String)
    }

    typealias Tab = AthletesMessages.Tab

    let athleteId: String
    private(set) var profile: AthleteProfile?
    private(set) var phase: Phase = .idle
    /// Plus's "Cette année : X km"; nil until loaded, or when it could not be.
    private(set) var yearToDateDistance: Distance?
    var tab = Tab.activities

    let follows: FollowStore
    let activities: AthleteActivitiesStore

    @ObservationIgnored private let loadProfile: LoadAthleteProfile
    @ObservationIgnored private let loadYearToDateDistance: LoadAthleteYearToDateDistance
    @ObservationIgnored private var generation = 0

    init(
        athleteId: String,
        loadProfile: LoadAthleteProfile,
        loadYearToDateDistance: LoadAthleteYearToDateDistance,
        follows: FollowStore,
        activities: AthleteActivitiesStore
    ) {
        self.athleteId = athleteId
        self.loadProfile = loadProfile
        self.loadYearToDateDistance = loadYearToDateDistance
        self.follows = follows
        self.activities = activities
    }

    /// The follow button's state; nil until loaded.
    var followStatus: FollowStatus? { follows.status(of: athleteId) }

    /// First appearance: loads once.
    func load() async {
        guard phase == .idle else { return }
        await refresh()
    }

    /// Pull-to-refresh and "Réessayer": the header, Plus's figure and the Activities again.
    func refresh() async {
        generation += 1
        let current = generation
        if profile == nil {
            phase = .loading
        }
        async let activitiesLoaded: Void = activities.refresh(athleteId: athleteId)
        async let distance = try? loadYearToDateDistance(athleteId: athleteId)
        do {
            let loaded = try await loadProfile(athleteId: athleteId)
            guard current == generation else { return }
            profile = loaded
            follows.track(athleteId, status: loaded.viewerFollowStatus)
            phase = .loaded
        } catch {
            guard current == generation else { return }
            if profile == nil {
                phase = .failed(message: AthletesMessages.message(for: error))
            }
        }
        let yearToDate = await distance
        await activitiesLoaded
        guard current == generation else { return }
        yearToDateDistance = yearToDate ?? yearToDateDistance
    }

    /// "Suivre".
    func follow() async {
        await change { await $0.follows.follow($0.athleteId) }
    }

    /// "Se désabonner", or a tap on "Demande envoyée".
    func unfollow() async {
        await change { await $0.follows.unfollow($0.athleteId) }
    }

    /// The counter takes the server's value at once. Becoming, or no longer being, an accepted
    /// follower changes which Activities the viewer may see, so everything is reloaded.
    private func change(_ send: (AthleteProfileStore) async -> FollowChange?) async {
        let wasFollowing = followStatus == .accepted
        guard let change = await send(self) else { return }
        profile?.followerCount = change.followerCount
        if wasFollowing != (change.status == .accepted) {
            await refresh()
        }
    }
}
