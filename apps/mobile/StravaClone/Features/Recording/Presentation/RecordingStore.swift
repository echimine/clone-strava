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

    /// - Parameter ensureFullAccuracy: asks for temporary full accuracy when only the approximate
    ///   location is allowed; `false` when refused (ADR-031 §2).
    init(
        service: RecordingService,
        preferences: any RecordingPreferences,
        ensureFullAccuracy: @escaping @MainActor () async -> Bool
    ) {
        self.service = service
        self.preferences = preferences
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
