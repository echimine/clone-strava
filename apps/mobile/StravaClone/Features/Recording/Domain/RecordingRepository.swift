import Foundation

/// Persistence port: points are written as they come so nothing is lost if the app is killed (ADR-006).
protocol RecordingRepository: Sendable {
    func create(_ recording: ActiveRecording) async throws
    func append(_ sample: LocationSample, to id: ActivityID) async throws
    func finish(_ id: ActivityID, at date: Date) async throws
}
