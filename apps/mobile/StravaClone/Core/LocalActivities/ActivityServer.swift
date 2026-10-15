import Foundation

/// What `POST /v1/activities` answers (ADR-019 §1, ADR-031 §14).
enum ActivityCreation: Equatable, Sendable {
    /// `pending` on the server: the trace goes to this URL.
    case awaitingTrace(TraceUploadTarget)
    /// `200` without URL: the server already has the trace.
    case alreadyProcessing
}

/// `processingStatus` of `GET /v1/activities/:id` (ADR-031 §13).
enum RemoteActivityStatus: Equatable, Sendable {
    case pending, processing, processed
    /// `processingError` (`invalid_trace`, `empty_trace`, `processing_error`) when given.
    case failed(reason: String?)
}

/// Failures of the creation flow, as the response table of ADR-031 §14 needs them.
enum ActivityServerError: Error, Equatable, Sendable {
    /// No network, timeout, transport failure.
    case offline
    /// `5xx`.
    case unavailable
    case unauthorized
    /// `403` from the bucket: the pre-signed URL expired.
    case uploadURLExpired
    /// `409` on `upload-url`: the Activity is no longer `pending`.
    case notPending
    /// `409 trace_missing` on `complete`.
    case traceMissing
    /// A definitive refusal (`422`, `409 id_conflict`, `409 trace_too_large`,
    /// `409 activity_failed`, `404`…), with the server's code.
    case refused(code: String)

    var isRetryable: Bool {
        self == .offline || self == .unavailable
    }
}

/// The server side of a local Activity's journey (ADR-019 §1-4, ADR-031 §13): implemented over
/// the API and the bucket by `APIActivityServer`.
protocol ActivityServer: Sendable {
    func create(_ activity: LocalActivity) async throws(ActivityServerError) -> ActivityCreation
    func renewUploadURL(for id: ActivityID) async throws(ActivityServerError) -> TraceUploadTarget
    /// `PUT` of the gzipped trace, over a regular `URLSession` (ADR-031 §14).
    func uploadTrace(_ data: Data, to target: TraceUploadTarget) async throws(ActivityServerError)
    func complete(_ id: ActivityID) async throws(ActivityServerError)
    func status(of id: ActivityID) async throws(ActivityServerError) -> RemoteActivityStatus
    /// `DELETE /v1/activities/:id` (ADR-031 §13): an Activity already gone (`404`) counts as deleted.
    func delete(_ id: ActivityID) async throws(ActivityServerError)
}
