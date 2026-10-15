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
    @ObservationIgnored private let autoPausePreferences: (any AutoPausePreferences)?
    @ObservationIgnored private let requestMotionAuthorization: @MainActor () async -> Bool
    /// The auto-pause switch per sport on the pre-start screen (ADR-031 §4).
    private var autoPauseChoices: [RecordingSport: Bool] = [:]

    /// - Parameter ensureFullAccuracy: asks for temporary full accuracy when only the approximate
    ///   location is allowed; `false` when refused (ADR-031 §2).
    /// - Parameter requestMotionAuthorization: asks for "Motion & Fitness" access when the
    ///   switch is turned on for a run; `false` when refused (ADR-031 §4).
    init(
        service: RecordingService,
        preferences: any RecordingPreferences,
        ensureFullAccuracy: @escaping @MainActor () async -> Bool,
        autoPausePreferences: (any AutoPausePreferences)? = nil,
        requestMotionAuthorization: @escaping @MainActor () async -> Bool = { true }
    ) {
        self.service = service
        self.preferences = preferences
        self.ensureFullAccuracy = ensureFullAccuracy
        self.autoPausePreferences = autoPausePreferences
        self.requestMotionAuthorization = requestMotionAuthorization
        sport = preferences.lastSavedSport ?? .run
        for sport in RecordingSport.allCases {
            autoPauseChoices[sport] = autoPausePreferences?.autoPause(for: sport) ?? sport.autoPauseByDefault
        }
    }

    /// The sport of the pre-start screen, or of the Recording in progress, has an automatic Pause.
    var offersAutoPause: Bool {
        (snapshot?.recording.sport ?? sport).autoPauseRule != nil
    }

    /// The auto-pause switch: the Recording's during a Recording, else the sport's.
    var autoPause: Bool {
        if let recording = snapshot?.recording { return recording.autoPauseEnabled }
        return offersAutoPause && autoPauseChoices[sport] == true
    }

    /// Remembered per sport; turned on for a run, it asks for Motion access first and goes
    /// back off when refused. During a Recording it also changes the Recording's switch.
    func setAutoPause(_ enabled: Bool) async {
        let sport = snapshot?.recording.sport ?? sport
        guard sport.autoPauseRule != nil else { return }
        if enabled, sport.autoPauseRule == .motion, !(await requestMotionAuthorization()) {
            autoPauseChoices[sport] = false
            return
        }
        autoPauseChoices[sport] = enabled
        autoPausePreferences?.rememberAutoPause(enabled, for: sport)
        if snapshot != nil {
            await perform { try await $0.setAutoPause(enabled) }
        }
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
            snapshot = try await service.start(sport: sport, autoPause: autoPause)
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
