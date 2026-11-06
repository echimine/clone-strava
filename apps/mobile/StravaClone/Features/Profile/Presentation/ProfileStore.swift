import Foundation
import Observation
import SwiftUI

/// The Profile tab (ADR-036 §3, §10): my header and counters, the Progrès · Activités · Galerie
/// · Plus tabs (ADR-037 §10), "Modifier le profil", "Approuver mes abonnés" in Réglages, and the tab's navigation.
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
        case progress, activities, gallery, more
    }

    /// Screens of the profile's own stack; Activity details and Kudos and comments screens are
    /// pushed with their Core requests.
    enum Destination: Hashable {
        case settings
        case itineraries
        /// Plus › « Segments »: my favourite Segments (ADR-039 §15).
        case segments
        /// The magnifier: the athlete search (ADR-036 §2).
        case search
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
    let progress: ProfileProgressStore
    /// Galerie (ADR-037 §9), loaded when its tab first opens.
    let gallery: AthleteGalleryStore
    /// My photo, changed from the header or "Modifier le profil" (ADR-037 §2).
    let avatar: AvatarEditor

    @ObservationIgnored private let loadProfile: LoadProfile
    @ObservationIgnored private let loadYearToDateDistance: LoadYearToDateDistance
    @ObservationIgnored private let loadEditableProfile: LoadEditableProfile
    @ObservationIgnored private let updateProfile: UpdateProfile
    @ObservationIgnored private let setApproveFollowersUseCase: SetApproveFollowers
    @ObservationIgnored private var athleteId: String?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var approvalInFlight = false

    init(
        loadProfile: LoadProfile,
        loadYearToDateDistance: LoadYearToDateDistance,
        loadEditableProfile: LoadEditableProfile,
        updateProfile: UpdateProfile,
        setApproveFollowers: SetApproveFollowers,
        activities: ProfileActivitiesStore,
        progress: ProfileProgressStore,
        gallery: AthleteGalleryStore,
        avatar: AvatarEditor
    ) {
        self.loadProfile = loadProfile
        self.loadYearToDateDistance = loadYearToDateDistance
        self.loadEditableProfile = loadEditableProfile
        self.updateProfile = updateProfile
        self.setApproveFollowersUseCase = setApproveFollowers
        self.activities = activities
        self.progress = progress
        self.gallery = gallery
        self.avatar = avatar
        avatar.changed = { [weak self] url in self?.showAvatar(url) }
    }

    /// "Approuver mes abonnés", as shown: the server's value, or the one just chosen.
    var approveFollowers: Bool { profile?.approveFollowers ?? false }

    /// First appearance for this athlete: loads once.
    func load(athleteId: String) async {
        guard self.athleteId != athleteId || phase == .idle else { return }
        self.athleteId = athleteId
        await refresh()
    }

    /// Pull-to-refresh and "Réessayer": the header, Plus's figure, the Activities and, once
    /// opened, the Gallery again.
    func refresh() async {
        guard let athleteId else { return }
        generation += 1
        let current = generation
        if profile == nil {
            phase = .loading
        }
        async let activitiesLoaded: Void = activities.refresh(athleteId: athleteId)
        async let progressLoaded: Void = refreshProgressIfShown()
        async let galleryLoaded: Void = gallery.refresh()
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
        await progressLoaded
        await galleryLoaded
        guard current == generation else { return }
        yearToDateDistance = yearToDate ?? yearToDateDistance
    }

    /// What "Modifier le profil" starts from, or what went wrong.
    func editableProfile() async -> Result<EditableProfile, EditProfileFailure> {
        do {
            return .success(try await loadEditableProfile())
        } catch {
            return .failure(EditProfileFailure(message: ProfileMessages.message(for: error)))
        }
    }

    /// "Modifier le profil"'s Enregistrer: nil once the header shows the new name and the main
    /// sport leads my sports, else what went wrong. An invalid field is not sent.
    func save(_ edited: EditableProfile) async -> String? {
        let update: ProfileUpdate
        switch ProfileUpdate.validate(edited) {
        case .success(let valid): update = valid
        case .failure(let invalid): return ProfileMessages.message(for: invalid)
        }
        do {
            let athlete = try await updateProfile(update)
            profile?.athlete = athlete
            if let mainSport = update.mainSport, let sports = profile?.practicedSports {
                profile?.practicedSports = [mainSport] + sports.filter { $0 != mainSport }
            }
            return nil
        } catch {
            return ProfileMessages.message(for: error)
        }
    }

    /// My new photo once stored, or my initials once removed: the header follows.
    private func showAvatar(_ url: URL?) {
        guard let athlete = profile?.athlete else { return }
        profile?.athlete = ActivityAuthor(id: athlete.id, displayName: athlete.displayName, avatarURL: url)
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

    func openSegments() {
        path.append(Destination.segments)
    }

    func openSearch() {
        path.append(Destination.search)
    }

    /// My followers or following lists (ADR-036 §1), from my counters; nil until my profile loads.
    func followsRequest(_ list: AthleteFollowsRequest.Kind) -> AthleteFollowsRequest? {
        profile.map { AthleteFollowsRequest(profile: $0, list: list) }
    }

    /// A tap on "N abonnés" or "N abonnements".
    func openFollows(_ list: AthleteFollowsRequest.Kind) {
        guard let request = followsRequest(list) else { return }
        path.append(request)
    }

    /// What my follow screens changed (a request answered, a follower removed, an athlete
    /// followed): my counters follow without reloading.
    func apply(_ change: FollowCountsChange) {
        profile?.apply(change)
    }

    /// My Statistiques (ADR-036 §4), with my sports for its picker; nil until my profile loads.
    var statisticsRequest: AthleteStatisticsRequest? {
        profile.map { AthleteStatisticsRequest(athleteId: $0.athlete.id, sports: $0.practicedSports) }
    }

    /// Plus's Statistiques row.
    func openStatistics() {
        guard let statisticsRequest else { return }
        path.append(statisticsRequest)
    }

    /// The Galerie tab opened (ADR-037 §13); nothing before my profile is known.
    func openGallery() async {
        guard let athleteId else { return }
        await gallery.open(athleteId: athleteId, isOwn: true)
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
        progress.reset()
        gallery.reset()
        avatar.reset()
    }

    /// Progrès loads when its tab first appears: pull-to-refresh only reloads it once shown.
    private func refreshProgressIfShown() async {
        guard progress.phase != .idle else { return }
        await progress.refresh()
    }
}

/// Why "Modifier le profil" could not load, said to the athlete.
struct EditProfileFailure: Error, Equatable {
    let message: String
}
