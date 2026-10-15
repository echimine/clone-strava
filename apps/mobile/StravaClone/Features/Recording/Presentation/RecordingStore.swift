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

    @ObservationIgnored private let service: RecordingService
    @ObservationIgnored private let preferences: any RecordingPreferences
    @ObservationIgnored private let ensureFullAccuracy: @MainActor () async -> Bool
    @ObservationIgnored private let saveRecording: SaveRecording
    @ObservationIgnored private let cachedDefaultVisibility: @MainActor () -> ActivityVisibility

    /// - Parameters:
    ///   - ensureFullAccuracy: asks for temporary full accuracy when only the approximate
    ///     location is allowed; `false` when refused (ADR-031 §2).
    ///   - defaultVisibility: the athlete's cached `defaultVisibility` (ADR-031 §11, §13).
    init(
        service: RecordingService,
        preferences: any RecordingPreferences,
        ensureFullAccuracy: @escaping @MainActor () async -> Bool,
        saveRecording: SaveRecording,
        defaultVisibility: @escaping @MainActor () -> ActivityVisibility
    ) {
        self.service = service
        self.preferences = preferences
        self.ensureFullAccuracy = ensureFullAccuracy
        self.saveRecording = saveRecording
        cachedDefaultVisibility = defaultVisibility
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
            snapshot = try await service.start(sport: sport)
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

    /// Title prefilled on the finish screen (ADR-031 §11): the server's formula at Start.
    var defaultTitle: String {
        guard let recording = snapshot?.recording else { return "" }
        return DefaultActivityTitle.make(sport: recording.sport, startedAt: recording.startedAt)
    }

    /// Visibility preselected on the finish screen: the cached `defaultVisibility`, `public`
    /// if it was never loaded.
    var defaultVisibility: ActivityVisibility {
        cachedDefaultVisibility()
    }

    /// Save (ADR-031 §11): the local Activity is written and queued, the Record tab returns to
    /// the pre-start screen with this sport preselected. `true` once saved.
    func save(title: String, visibility: ActivityVisibility) async -> Bool {
        guard !isBusy, let recording = snapshot?.recording else { return false }
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        do {
            try await saveRecording(title: title, visibility: visibility)
        } catch {
            errorMessage = RecordingMessages.saveFailed
            return false
        }
        preferences.rememberSavedSport(recording.sport)
        sport = recording.sport
        snapshot = nil
        return true
    }

    /// After the confirmation: everything is wiped, back to the pre-start screen.
    func delete() async {
        await perform { service in
            try await service.delete()
            return nil
        }
    }

    private func perform(_ action: (RecordingService) async throws -> RecordingSnapshot?) async {
        errorMessage = nil
        do {
            snapshot = try await action(service)
        } catch {
            errorMessage = RecordingMessages.actionFailed
        }
    }
}
