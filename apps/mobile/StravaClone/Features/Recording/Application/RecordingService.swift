import Foundation

/// Coordinates a recording over time: GPS stream, persistence of each point,
/// provisional distance (ADR-007: services holding shared state are actors).
actor RecordingService {
    private let locationProvider: any LocationProvider
    private let repository: any RecordingRepository
    private let startRecording: StartRecording
    private var consumer: Task<Void, Never>?
    private var recording: ActiveRecording?

    init(locationProvider: any LocationProvider, repository: any RecordingRepository) {
        self.locationProvider = locationProvider
        self.repository = repository
        self.startRecording = StartRecording(repository: repository)
    }

    /// Starts recording and returns the successive states of the recording.
    func start() async throws -> AsyncStream<ActiveRecording> {
        let recording = try await startRecording()
        self.recording = recording
        let (updates, continuation) = AsyncStream<ActiveRecording>.makeStream(bufferingPolicy: .bufferingNewest(1))
        continuation.yield(recording)

        let samples = await locationProvider.start()
        consumer = Task {
            for await sample in samples {
                guard let updated = await self.record(sample) else { break }
                continuation.yield(updated)
            }
            continuation.finish()
        }
        return updates
    }

    func stop() async throws {
        await locationProvider.stop()
        consumer?.cancel()
        consumer = nil
        if let recording {
            try await repository.finish(recording.id, at: Date())
        }
        recording = nil
    }

    private func record(_ sample: LocationSample) async -> ActiveRecording? {
        guard var recording else { return nil }
        recording.append(sample)
        self.recording = recording
        // TODO(ADR-008): surface persistence failures instead of dropping them.
        try? await repository.append(sample, to: recording.id)
        return recording
    }
}
