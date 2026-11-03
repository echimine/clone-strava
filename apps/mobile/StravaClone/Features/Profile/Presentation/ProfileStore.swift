import Foundation
import Observation
import SwiftUI

/// The Profile tab (ADR-036 §3, §10): my header and counters, the Progrès · Activités · Plus
/// tabs, "Modifier le profil", "Approuver mes abonnés" in Réglages, and the tab's navigation.
/// One for the app, reset at sign-out.
@Observable
@MainActor
final class ProfileStore {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(message: String)
    }

    enum Tab: Hashable, CaseIterable {
        case progress, activities, more
    }

    /// Screens of the profile's own stack; Activity details and Kudos and comments screens are
    /// pushed with their Core requests.
    enum Destination: Hashable {
        case settings
        case itineraries
    }

    private(set) var profile: AthleteProfile?
    private(set) var phase: Phase = .idle
    /// Plus's "Cette année : X km"; nil until loaded, or when it could not be.
    private(set) var yearToDateDistance: Distance?
    var tab = Tab.activities
    /// Navigation of the Profile tab (ADR-036 §10).
    var path = NavigationPath()
    /// Short message over the tab (a setting the server turned down).
    var toast: String?

    let activities: ProfileActivitiesStore

    @ObservationIgnored private let loadProfile: LoadProfile
    @ObservationIgnored private let loadYearToDateDistance: LoadYearToDateDistance
    @ObservationIgnored private let renameAthlete: RenameAthlete
    @ObservationIgnored private let setApproveFollowersUseCase: SetApproveFollowers
    @ObservationIgnored private var athleteId: String?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var approvalInFlight = false

    init(
        loadProfile: LoadProfile,
        loadYearToDateDistance: LoadYearToDateDistance,
        renameAthlete: RenameAthlete,
        setApproveFollowers: SetApproveFollowers,
        activities: ProfileActivitiesStore
    ) {
        self.loadProfile = loadProfile
        self.loadYearToDateDistance = loadYearToDateDistance
        self.renameAthlete = renameAthlete
        self.setApproveFollowersUseCase = setApproveFollowers
        self.activities = activities
    }

    /// "Approuver mes abonnés", as shown: the server's value, or the one just chosen.
    var approveFollowers: Bool { profile?.approveFollowers ?? false }

    /// First appearance for this athlete: loads once.
    func load(athleteId: String) async {
        guard self.athleteId != athleteId || phase == .idle else { return }
        self.athleteId = athleteId
        await refresh()
    }

    /// Pull-to-refresh and "Réessayer": the header, Plus's figure and the Activities again.
    func refresh() async {
        guard let athleteId else { return }
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
            phase = .loaded
        } catch {
            guard current == generation else { return }
            if profile == nil {
                phase = .failed(message: ProfileMessages.message(for: error))
            }
        }
        let yearToDate = await distance
        await activitiesLoaded
        guard current == generation else { return }
        yearToDateDistance = yearToDate ?? yearToDateDistance
    }

    /// "Modifier le profil": nil once the header shows the new name, else what went wrong.
    func rename(firstName: String, lastName: String) async -> String? {
        guard let name = ProfileName(firstName: firstName, lastName: lastName) else {
            return ProfileMessages.invalidName
        }
        do {
            let athlete = try await renameAthlete(name)
            profile?.athlete = athlete
            return nil
        } catch {
            return ProfileMessages.message(for: error)
        }
    }

    /// Optimistic: the switch moves at once, then takes the server's value, or goes back with
    /// a toast. A change while one is in flight is ignored.
    func setApproveFollowers(_ approve: Bool) async {
        guard !approvalInFlight, profile != nil else { return }
        let previous = profile?.approveFollowers
        profile?.approveFollowers = approve
        approvalInFlight = true
        defer { approvalInFlight = false }
        do {
            let saved = try await setApproveFollowersUseCase(approve)
            profile?.approveFollowers = saved
        } catch {
            profile?.approveFollowers = previous
            toast = ProfileMessages.approvalFailed
        }
    }

    func openSettings() {
        path.append(Destination.settings)
    }

    func openItineraries() {
        path.append(Destination.itineraries)
    }

    /// A tap on a card outside its buttons (ADR-033 §1).
    func openActivity(_ id: ActivityID) {
        path.append(ActivityDetailRequest(id: id))
    }

    /// The card's comment button (ADR-036 §8).
    func openComments(_ id: ActivityID) {
        path.append(ActivityEngagementRequest.comments(id))
    }

    /// Sign-out: forgets the previous account's profile.
    func reset() {
        generation += 1
        athleteId = nil
        profile = nil
        phase = .idle
        yearToDateDistance = nil
        tab = .activities
        path = NavigationPath()
        toast = nil
        activities.reset()
    }
}
