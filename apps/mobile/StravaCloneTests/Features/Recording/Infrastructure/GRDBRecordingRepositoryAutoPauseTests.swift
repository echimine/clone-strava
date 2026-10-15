import Foundation
import Testing
@testable import StravaClone

/// The kind and position of the Pause in progress and the auto-pause switch are saved with the
/// Recording (ADR-031 §10): a relaunch by iOS keeps an automatic Pause automatic.
struct GRDBRecordingRepositoryAutoPauseTests {
    private let start = Date(timeIntervalSince1970: 1_792_047_600)

    @Test func savesTheAutomaticPauseAndTheSwitch() async throws {
        let repository = GRDBRecordingRepository(database: try AppDatabase.inMemory())
        var recording = Recording(sport: .ride, startedAt: start, autoPauseEnabled: true)
        try await repository.create(recording)

        recording.pause(at: start.addingTimeInterval(40), kind: .automatic, position: Coordinate(latitude: 45.764, longitude: 4.8357))
        try await repository.save(recording)

        let stored = try #require(try await repository.load()?.recording)
        #expect(stored == recording)
        #expect(stored.isAutomaticallyPaused)
        #expect(stored.autoPauseEnabled)
    }

    @Test func aManualPauseStaysManual() async throws {
        let repository = GRDBRecordingRepository(database: try AppDatabase.inMemory())
        var recording = Recording(sport: .run, startedAt: start)
        try await repository.create(recording)

        recording.pause(at: start.addingTimeInterval(40))
        try await repository.save(recording)

        let stored = try #require(try await repository.load()?.recording)
        #expect(stored.currentPauseKind == .manual)
        #expect(!stored.autoPauseEnabled)
    }
}
