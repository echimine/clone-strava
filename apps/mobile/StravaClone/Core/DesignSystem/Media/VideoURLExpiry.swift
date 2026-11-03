import AVFoundation

/// A video whose pre-signed URL expired (ADR-037 §1). `AVPlayer` reads the URL itself, so the
/// bucket's `403` only shows as the item's error: CoreMedia's "HTTP 403: Forbidden" under it,
/// or a `403` in its error log. A `404` (object deleted) is not one: nothing to reload.
enum VideoURLExpiry {
    /// `CoreMediaErrorDomain` code of "HTTP 403: Forbidden".
    static let coreMediaForbidden = -12_660

    static func isExpired(error: (any Error)?, logStatusCodes: [Int]) -> Bool {
        if logStatusCodes.contains(where: { $0 == 403 || $0 == coreMediaForbidden }) { return true }
        guard let error else { return false }
        return isForbidden(error as NSError)
    }

    static func isExpired(_ item: AVPlayerItem) -> Bool {
        isExpired(error: item.error, logStatusCodes: item.errorLog()?.events.map(\.errorStatusCode) ?? [])
    }

    private static func isForbidden(_ error: NSError) -> Bool {
        if error.domain == "CoreMediaErrorDomain", error.code == coreMediaForbidden { return true }
        var underlying = (error.userInfo[NSMultipleUnderlyingErrorsKey] as? [NSError]) ?? []
        if let single = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            underlying.append(single)
        }
        return underlying.contains(where: isForbidden)
    }
}

/// Calls `expired` when the player's current item fails on an expired URL: the screen's
/// `\.imageURLExpired` action, as for an image (ADR-037 §1).
final class VideoURLExpiryObserver {
    private var observation: NSKeyValueObservation?

    init(player: AVPlayer, expired: @escaping @MainActor () -> Void) {
        observation = player.observe(\.currentItem?.status, options: [.initial, .new]) { player, _ in
            guard let item = player.currentItem, item.status == .failed, VideoURLExpiry.isExpired(item) else { return }
            Task { @MainActor in expired() }
        }
    }

    deinit {
        observation?.invalidate()
    }
}
