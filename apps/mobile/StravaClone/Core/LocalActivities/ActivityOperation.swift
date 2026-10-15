import Foundation

/// The steps of a local Activity's journey to the server (ADR-031 §14), one `sync_operation`
/// row at a time per Activity: each success replaces its row with the next one, in the
/// transaction that changes the Activity's state.
enum ActivityOperationStep: String, CaseIterable, Sendable {
    case create = "create_activity"
    case upload = "upload_trace"
    case complete = "complete_activity"
    /// `DELETE /v1/activities/:id` of an Activity deleted on the phone after its creation
    /// (ADR-031 §14): the local copy stays, hidden, until the server answers.
    case delete = "delete_activity"
}

extension ActivityServerError {
    /// How `sync_operation.last_error` keeps a temporary failure.
    var storedCode: String {
        switch self {
        case .offline: "offline"
        case .unavailable: "unavailable"
        case .unauthorized: "unauthorized"
        case .uploadURLExpired: "uploadURLExpired"
        case .notPending: "notPending"
        case .traceMissing: "traceMissing"
        case .refused(let code): "refused:\(code)"
        }
    }

    init?(storedCode: String) {
        switch storedCode {
        case "offline": self = .offline
        case "unavailable": self = .unavailable
        case "unauthorized": self = .unauthorized
        case "uploadURLExpired": self = .uploadURLExpired
        case "notPending": self = .notPending
        case "traceMissing": self = .traceMissing
        default:
            guard storedCode.hasPrefix("refused:") else { return nil }
            self = .refused(code: String(storedCode.dropFirst("refused:".count)))
        }
    }
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
    /// The last temporary failure (`offline`, `unavailable`…), nil before the first attempt.
    var lastError: ActivityServerError?
    /// `upload_trace` only: the URL received from `POST /v1/activities` or `upload-url`.
    let uploadTarget: TraceUploadTarget?
}
