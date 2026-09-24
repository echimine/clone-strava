import Foundation

/// Use case: creates a recording with a client-generated UUID (ADR-008 §4) and persists it.
struct StartRecording: Sendable {
    let repository: any RecordingRepository
    let now: @Sendable () -> Date

    init(repository: any RecordingRepository, now: @escaping @Sendable () -> Date = Date.init) {
        self.repository = repository
        self.now = now
    }

    func callAsFunction() async throws -> ActiveRecording {
        let recording = ActiveRecording(startedAt: now())
        try await repository.create(recording)
        return recording
    }
}
