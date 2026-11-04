import Foundation
import os

/// `MediaFileTransferring` over a background `URLSession` (ADR-037 §5): uploads go on while
/// the app is suspended or killed, over cellular data too (`allowsCellularAccess`, not
/// `isDiscretionary`). It must be created at launch, before iOS hands the events of tasks
/// finished meanwhile (`handleEventsForBackgroundURLSession`); `finishEvents` is that call's
/// completion handler, run once the delegate has received them all.
final class BackgroundMediaTransfer: NSObject, MediaFileTransferring, URLSessionTaskDelegate, @unchecked Sendable {
    static let identifier = "fr.echimine.stravaclone.media-upload"

    let events: AsyncStream<MediaTransferEvent>
    private let continuation: AsyncStream<MediaTransferEvent>.Continuation
    private let finishEvents = OSAllocatedUnfairLock<(@Sendable () -> Void)?>(initialState: nil)
    /// Set once in `init`, read-only afterwards.
    private var session: URLSession!

    init(identifier: String = BackgroundMediaTransfer.identifier) {
        (events, continuation) = AsyncStream.makeStream(of: MediaTransferEvent.self)
        super.init()
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.allowsCellularAccess = true
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    /// `application(_:handleEventsForBackgroundURLSession:completionHandler:)` for this session.
    func handleEvents(for identifier: String, completionHandler: @escaping @Sendable () -> Void) -> Bool {
        guard identifier == session.configuration.identifier else { return false }
        finishEvents.withLock { $0 = completionHandler }
        return true
    }

    func start(_ put: MediaFilePut) async {
        var request = URLRequest(url: put.destination)
        request.httpMethod = "PUT"
        request.setValue(put.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(String(put.contentLength), forHTTPHeaderField: "Content-Length")
        let task = session.uploadTask(with: request, fromFile: put.file)
        task.taskDescription = put.key.description
        task.resume()
    }

    func cancel(mediaIDs: Set<UUID>) async {
        for task in await session.allTasks {
            guard let key = task.taskDescription.flatMap(MediaFileKey.init), mediaIDs.contains(key.mediaID) else { continue }
            task.cancel()
        }
    }

    func cancelAll() async {
        for task in await session.allTasks {
            task.cancel()
        }
    }

    func activeFiles() async -> Set<MediaFileKey> {
        let tasks = await session.allTasks
        return Set(tasks.filter { $0.state == .running || $0.state == .suspended }.compactMap { $0.taskDescription.flatMap(MediaFileKey.init) })
    }

    // MARK: - URLSessionTaskDelegate

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard let key = task.taskDescription.flatMap(MediaFileKey.init) else { return }
        continuation.yield(.progress(key, sent: totalBytesSent, total: totalBytesExpectedToSend))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let key = task.taskDescription.flatMap(MediaFileKey.init) else { return }
        if let error = error as? URLError, error.code == .cancelled { return }
        if error == nil, let http = task.response as? HTTPURLResponse {
            continuation.yield(.finished(key, status: http.statusCode))
        } else {
            continuation.yield(.failed(key))
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        guard let finish = finishEvents.withLock({ handler -> (@Sendable () -> Void)? in
            defer { handler = nil }
            return handler
        }) else { return }
        // The events are handled on the main actor: the handler runs after them.
        Task { @MainActor in finish() }
    }
}
