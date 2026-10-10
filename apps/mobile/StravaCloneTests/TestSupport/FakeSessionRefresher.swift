import Foundation
@testable import StravaClone

/// Scripted `SessionRefreshing`: answers `succeeds`, counts the calls.
final class FakeSessionRefresher: SessionRefreshing, @unchecked Sendable {
    private let lock = NSLock()
    private var _succeeds: Bool
    private var _calls = 0

    init(succeeds: Bool = true) {
        _succeeds = succeeds
    }

    var calls: Int { lock.withLock { _calls } }

    func refresh() async -> Bool {
        lock.withLock {
            _calls += 1
            return _succeeds
        }
    }
}
