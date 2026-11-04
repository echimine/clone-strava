import Foundation

/// One file of one Media in the bucket's background session.
struct MediaFileKey: Hashable, Sendable, CustomStringConvertible {
    let mediaID: UUID
    let name: String

    /// The task's `taskDescription`: survives the app being killed and relaunched by iOS.
    var description: String { "\(mediaID.uuidString.lowercased())/\(name)" }

    init(mediaID: UUID, name: String) {
        self.mediaID = mediaID
        self.name = name
    }

    init?(_ description: String) {
        let parts = description.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[0]) else { return nil }
        self.init(mediaID: id, name: parts[1])
    }
}

/// A `PUT` of a local file to a pre-signed URL, with the signed headers.
struct MediaFilePut: Hashable, Sendable {
    let key: MediaFileKey
    let file: URL
    let destination: URL
    let contentType: String
    let contentLength: Int
}

/// What the background session tells about a `PUT`, possibly after a relaunch by iOS.
enum MediaTransferEvent: Hashable, Sendable {
    case progress(MediaFileKey, sent: Int64, total: Int64)
    /// The bucket answered: `2xx`, `403` (URL expired), `5xx`…
    case finished(MediaFileKey, status: Int)
    /// No answer (network lost for good, file unreadable). Not sent for a cancelled task.
    case failed(MediaFileKey)
}

/// The background `URLSession` of the Media files (ADR-037 §5), behind a protocol: a
/// background session takes no custom `URLProtocol`, so the queue's tests use a fake.
protocol MediaFileTransferring: Sendable {
    func start(_ put: MediaFilePut) async
    /// Cancels every task of these Media (no `.failed` event follows).
    func cancel(mediaIDs: Set<UUID>) async
    func cancelAll() async
    /// Files with a task still running, after a relaunch included.
    func activeFiles() async -> Set<MediaFileKey>
    /// The events, for the app's lifetime; one consumer (the queue).
    var events: AsyncStream<MediaTransferEvent> { get }
}
