import Foundation

/// The steps of a local Activity's journey to the server (ADR-031 §14), one `sync_operation`
/// row at a time per Activity: each success replaces its row with the next one, in the
/// transaction that changes the Activity's state.
enum ActivityOperationStep: String, CaseIterable, Sendable {
    case create = "create_activity"
    case upload = "upload_trace"
    case complete = "complete_activity"
}

/// A pre-signed `PUT` of the trace (ADR-019 §1-2): valid 15 minutes.
struct TraceUploadTarget: Codable, Equatable, Sendable {
    let url: URL
    let expiresAt: Date
}

/// One queued step of a local Activity, as stored in `sync_operation`.
struct PendingActivityOperation: Equatable, Sendable {
    let id: Int64
    let activityID: ActivityID
    let step: ActivityOperationStep
    let attempts: Int
    let nextAttemptAt: Date
    /// `upload_trace` only: the URL received from `POST /v1/activities` or `upload-url`.
    let uploadTarget: TraceUploadTarget?
}
