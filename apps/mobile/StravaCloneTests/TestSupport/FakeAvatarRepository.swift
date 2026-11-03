import Foundation
@testable import StravaClone

/// In-memory `AvatarRepository` (ADR-025 §3): scripted answers, recorded calls. An upload can
/// be held until `release()`, to look at the screen while it is sending.
final class FakeAvatarRepository: AvatarRepository, @unchecked Sendable {
    var uploadResult: Result<URL?, AvatarError> = .success(URL(string: "https://bucket.test/avatars/me/new.jpg?X-Amz-Signature=a"))
    var removeResult: Result<Void, AvatarError> = .success(())
    /// When true, `upload` waits for `release()`.
    var holdsUploads = false

    private let lock = NSLock()
    private var held: [CheckedContinuation<Void, Never>] = []
    private var sent: [Data] = []
    private var removals = 0

    var uploads: [Data] { lock.withLock { sent } }
    var removeCount: Int { lock.withLock { removals } }

    func upload(_ jpeg: Data) async throws(AvatarError) -> URL? {
        lock.withLock { sent.append(jpeg) }
        if holdsUploads {
            await withCheckedContinuation { continuation in
                lock.withLock { held.append(continuation) }
            }
        }
        return try uploadResult.get()
    }

    func remove() async throws(AvatarError) {
        lock.withLock { removals += 1 }
        try removeResult.get()
    }

    /// Lets the held uploads answer.
    func release() {
        let continuations = lock.withLock {
            defer { held = [] }
            return held
        }
        continuations.forEach { $0.resume() }
    }

    var hasHeldUpload: Bool { lock.withLock { !held.isEmpty } }
}
