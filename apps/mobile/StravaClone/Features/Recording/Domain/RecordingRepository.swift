import Foundation

/// What is stored of the Recording in progress (ADR-031 §10): its row, finished Pauses and raw
/// points. Timer, distance and speeds are recomputed from them.
struct StoredRecording: Equatable, Sendable {
    let recording: Recording
    /// Raw points in time order, as written (no accuracy filter).
    let points: [LocationSample]
    /// The Itinerary followed, with its saved progress (ADR-031 §10).
    var itinerary: FollowedItinerary? = nil
}

enum RecordingRepositoryError: Error, Equatable {
    /// Only one Recording exists at a time.
    case alreadyExists
}

/// Persistence port of the Recording (ADR-031 §10): every point is on disk within a second,
/// so nothing is lost if the app is killed.
protocol RecordingRepository: Sendable {
    /// The Recording in progress, if any.
    func load() async throws -> StoredRecording?
    /// Throws `RecordingRepositoryError.alreadyExists` while another Recording exists.
    func create(_ recording: Recording) async throws
    /// Saves the phase and the Pause in progress, and the newly finished Pauses, in one transaction.
    func save(_ recording: Recording) async throws
    /// Writes one raw point in its own transaction, only while the Recording `id` is `active`.
    /// Returns `false` when nothing was written.
    @discardableResult
    func append(_ point: LocationSample, to id: ActivityID) async throws -> Bool
    /// Wipes the Recording, its points and its Pauses in one transaction.
    func delete(_ id: ActivityID) async throws
    /// Sets the Itinerary followed by the Recording `id`, its track and progress; `nil` clears it.
    func saveItinerary(_ itinerary: FollowedItinerary?, of id: ActivityID) async throws
    /// Saves the progress along the followed Itinerary of the Recording `id`.
    func saveItineraryProgress(_ progress: ItineraryProgress.Saved, of id: ActivityID) async throws
    /// Saves the Return path of the Recording `id` and its return point (ADR-031 §7); `nil` clears it.
    func saveReturnPath(_ returnPath: ReturnPath?, of id: ActivityID) async throws
}
