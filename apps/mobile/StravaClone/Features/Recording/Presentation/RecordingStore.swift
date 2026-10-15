import Foundation
import Observation

/// State of the Record tab (ADR-031 §2, §8, §11): pre-start screen, Recording in progress
/// or finish screen, following `RecordingService`.
@Observable
@MainActor
final class RecordingStore {
    enum Screen: Equatable {
        case loading, preStart, recording, finishing
    }

    /// The Recording in progress, `nil` on the pre-start screen.
    private(set) var snapshot: RecordingSnapshot?
    private(set) var isLoaded = false
    /// Sport chip of the pre-start screen.
    var sport: RecordingSport
    private(set) var isBusy = false
    var errorMessage: String?
    var toast: String?
    /// Itinerary chip of the pre-start screen (ADR-031 §2): the cached Itineraries, newest first.
    private(set) var itineraries: [CachedItineraryListing] = []
    /// "Aucun" by default, not remembered.
    private(set) var chosenItinerary: CachedItineraryListing?

    @ObservationIgnored private let service: RecordingService
    @ObservationIgnored private let preferences: any RecordingPreferences
    @ObservationIgnored private let itineraryCache: any ItineraryCacheReader
    @ObservationIgnored private let ensureFullAccuracy: @MainActor () async -> Bool

    /// - Parameter ensureFullAccuracy: asks for temporary full accuracy when only the approximate
    ///   location is allowed; `false` when refused (ADR-031 §2).
    init(
        service: RecordingService,
        preferences: any RecordingPreferences,
        itineraries: any ItineraryCacheReader,
        ensureFullAccuracy: @escaping @MainActor () async -> Bool
    ) {
        self.service = service
        self.preferences = preferences
        itineraryCache = itineraries
        self.ensureFullAccuracy = ensureFullAccuracy
        sport = preferences.lastSavedSport ?? .run
    }

    var screen: Screen {
        guard isLoaded else { return .loading }
        switch snapshot?.recording.phase {
        case nil: return .preStart
        case .active, .paused: return .recording
        case .finishing: return .finishing
        }
    }

    /// Picks up a stored Recording, then follows the service until cancelled (SwiftUI `.task`).
    func observe() async {
        do {
            _ = try await service.restore()
        } catch {
            errorMessage = RecordingMessages.startFailed
        }
        for await snapshot in await service.snapshots() {
            self.snapshot = snapshot
            isLoaded = true
        }
    }

    func start() async {
        guard !isBusy, snapshot == nil else { return }
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        guard await ensureFullAccuracy() else {
            errorMessage = RecordingMessages.fullAccuracyRefused
            return
        }
        do {
            let wantsItinerary = chosenItinerary != nil
            let itinerary = try await loadChosenItinerary()
            // Deleted elsewhere: the chip is reset, the athlete decides again.
            guard itinerary != nil || !wantsItinerary else { return }
            snapshot = try await service.start(sport: sport, itinerary: itinerary)
        } catch {
            errorMessage = RecordingMessages.startFailed
        }
    }

    func pause() async {
        await perform { try await $0.pause() }
    }

    func resume() async {
        await perform { try await $0.resume() }
    }

    /// After the confirmation: opens the finish screen.
    func finish() async {
        await perform { try await $0.finish() }
    }

    /// "Reprendre" on the finish screen.
    func reopen() async {
        await perform { try await $0.reopen() }
    }

    /// After the confirmation: everything is wiped, back to the pre-start screen.
    func delete() async {
        await perform { service in
            try await service.delete()
            return nil
        }
    }

    /// "Retirer l'Itinéraire", after the confirmation.
    func removeItinerary() async {
        await perform { try await $0.removeItinerary() }
    }

    private func perform(_ action: (RecordingService) async throws -> RecordingSnapshot?) async {
        errorMessage = nil
        do {
            snapshot = try await action(service)
        } catch {
            errorMessage = RecordingMessages.actionFailed
        }
    }

    // MARK: - Itinerary (ADR-031 §2)

    /// Reads the cached Itineraries; a chosen one gone meanwhile resets the chip with a toast.
    func loadItineraries() async {
        guard let listed = try? await itineraryCache.cachedItineraries() else { return }
        itineraries = listed
        if let chosen = chosenItinerary, !listed.contains(where: { $0.id == chosen.id && $0.hasTrack }) {
            itineraryWasDeleted()
        }
    }

    /// `nil` for "Aucun". An Itinerary whose track is not on the phone cannot be chosen.
    /// Choosing one switches the sport to its sport; the athlete can change it back.
    func choose(_ listing: CachedItineraryListing?) {
        guard let listing else {
            chosenItinerary = nil
            return
        }
        guard listing.hasTrack else { return }
        chosenItinerary = listing
        if let sport = RecordingSport(rawValue: listing.sport.code) {
            self.sport = sport
        }
    }

    /// "Démarrer avec cet Itinéraire": the pre-start screen with the Itinerary chosen, never a
    /// Start by itself. Nothing changes while a Recording exists.
    func prepare(itineraryID: ItineraryID) async {
        guard snapshot == nil else { return }
        await loadItineraries()
        if let listing = itineraries.first(where: { $0.id == itineraryID }) {
            choose(listing)
        }
    }

    /// The chosen Itinerary's track, drawn on the pre-start map.
    func chosenItineraryTrack() async -> [Coordinate] {
        guard let id = chosenItinerary?.id else { return [] }
        return (try? await itineraryCache.track(of: id))?.points ?? []
    }

    /// The copy of the chosen Itinerary to follow; `nil` without one, or when it was deleted
    /// elsewhere (the chip is then reset with a toast).
    private func loadChosenItinerary() async throws -> FollowedItinerary? {
        guard let chosen = chosenItinerary else { return nil }
        guard let track = try await itineraryCache.track(of: chosen.id) else {
            itineraryWasDeleted()
            return nil
        }
        return FollowedItinerary(track, name: chosen.name)
    }

    private func itineraryWasDeleted() {
        chosenItinerary = nil
        toast = RecordingMessages.itineraryDeleted
    }
}
