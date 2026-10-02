import Foundation
@testable import StravaClone

/// In-memory `RecordingRepository` (ADR-025 §3) recording every call.
actor FakeRecordingRepository: RecordingRepository {
    private(set) var created: [ActiveRecording] = []
    private(set) var appended: [LocationSample] = []
    private(set) var finished: [ActivityID] = []

    func create(_ recording: ActiveRecording) async throws {
        created.append(recording)
    }

    func append(_ sample: LocationSample, to id: ActivityID) async throws {
        appended.append(sample)
    }

    func finish(_ id: ActivityID, at date: Date) async throws {
        finished.append(id)
    }
}
