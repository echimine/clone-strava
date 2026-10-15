import Foundation

/// Who sees an Activity (`activity.visibility`, ADR-017): Everyone, Followers, Only me.
enum ActivityVisibility: String, CaseIterable, Codable, Sendable {
    case `public`, followers, `private`
}

/// Local lifecycle of a saved Activity until the server has processed it (ADR-008 §2 as
/// amended by ADR-031 §1, §14): a Recording is not an Activity state, so it starts at `recorded`.
enum LocalActivityState: String, Codable, Sendable {
    /// Saved on the phone, `create_activity` queued.
    case recorded
    /// Known to the server (`pending`), `upload_trace` queued.
    case created
    /// Trace in the bucket, `complete_activity` queued.
    case traceUploaded = "trace_uploaded"
    /// Handed to the worker: followed with `GET /v1/activities/:id` until `processed`.
    case processing
    /// Refused by the API or failed by the worker; the points are kept.
    case failed
}

/// Why a local Activity is `failed` (ADR-031 §14): the server's code (`validation_error`,
/// `id_conflict`, `trace_too_large`, `activity_failed`, `invalid_trace`…), and the state to go
/// back to on Retry.
struct LocalActivityFailure: Equatable, Sendable {
    let reason: String
    let resumeState: LocalActivityState
}

/// An Activity saved on the phone and not yet processed by the server (ADR-031 §11, §14), with
/// its provisional values: no elevation gain. Its points and Pauses are stored under the same
/// UUID, the one generated at Start.
struct LocalActivity: Equatable, Sendable {
    let id: ActivityID
    let sport: SportType
    let title: String
    let visibility: ActivityVisibility
    let startedAt: Date
    /// Start of the last Pause: the final Pause is never sent.
    let endedAt: Date
    let distance: Distance
    /// The timer at the end: time minus Pauses.
    let movingTimeS: Int
    /// From Start to the end, Pauses included.
    let elapsedTimeS: Int
    var state: LocalActivityState = .recorded
    var failure: LocalActivityFailure?
}

/// Why Delete or Retry was turned down (ADR-031 §14): Delete only before `processing` (or once
/// `failed`), Retry only after an API refusal.
enum LocalActivityActionError: Error, Equatable, Sendable {
    case notAllowed
}

extension LocalActivity {
    /// Delete is offered before `processing`, and on `failed` (ADR-031 §14).
    var canBeDeleted: Bool { state != .processing }

    /// Retry is offered after an API refusal only: a worker failure (`failed` from
    /// `processing`) is retried from the backoffice.
    var canBeRetried: Bool {
        state == .failed && failure.map { $0.resumeState != .processing } ?? false
    }

    /// The server knows this Activity: `create_activity` succeeded.
    var isKnownToServer: Bool {
        switch state {
        case .recorded: false
        case .created, .traceUploaded, .processing: true
        case .failed: failure?.resumeState != .recorded
        }
    }
}

/// The Save transaction (ADR-031 §11), implemented by `Core/LocalActivities`: the local
/// Activity in `recorded`, `create_activity` in `sync_operation`, and the `recording` row
/// deleted, all at once. The points and finished Pauses stay attached to the Activity.
protocol LocalActivitySaving: Sendable {
    func saveRecorded(_ activity: LocalActivity) async throws
}

/// The visibility preselected on the finish screen (ADR-031 §11, §13): the athlete's
/// `defaultVisibility` from `GET /v1/me`, cached; `public` if it was never loaded.
protocol DefaultVisibilityProviding: Sendable {
    var cachedDefaultVisibility: ActivityVisibility { get }
}
