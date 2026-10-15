import Foundation
@testable import StravaClone

/// Simulated Live Activity port (ADR-031 §9): records every call; `startSucceeds = false`
/// plays a refusal (Live Activities off in Settings).
final class FakeRecordingLiveActivity: RecordingLiveActivity, @unchecked Sendable {
    enum Call: Equatable {
        case endAll
        case start(RecordingLiveActivityContent, staleDate: Date)
        case update(RecordingLiveActivityContent, staleDate: Date)
        case end(final: RecordingLiveActivityContent?)
    }

    private let lock = NSLock()
    private var _calls: [Call] = []
    private var _startSucceeds = true

    var calls: [Call] { lock.withLock { _calls } }

    var startSucceeds: Bool {
        get { lock.withLock { _startSucceeds } }
        set { lock.withLock { _startSucceeds = newValue } }
    }

    /// Contents sent by `start` and `update`, in order.
    var contents: [RecordingLiveActivityContent] {
        calls.compactMap {
            switch $0 {
            case let .start(content, _), let .update(content, _): content
            default: nil
            }
        }
    }

    var updateCount: Int {
        calls.filter { if case .update = $0 { true } else { false } }.count
    }

    /// Waits until the calls match `predicate`, at most `timeout`: then returns them as they
    /// are and the test's expectations fail.
    @MainActor @discardableResult
    func until(timeout: Duration = .seconds(2), _ predicate: ([Call]) -> Bool) async -> [Call] {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let calls = calls
            if predicate(calls) { return calls }
            await Task.yield()
        }
        return calls
    }

    /// Lets pending events through, then returns the calls: to check nothing more came.
    @MainActor
    func settled() async -> [Call] {
        await until(timeout: .milliseconds(200)) { _ in false }
    }

    func endAll() async {
        record(.endAll)
    }

    func start(_ content: RecordingLiveActivityContent, staleDate: Date) async -> Bool {
        record(.start(content, staleDate: staleDate))
        return startSucceeds
    }

    func update(_ content: RecordingLiveActivityContent, staleDate: Date) async {
        record(.update(content, staleDate: staleDate))
    }

    func end(final content: RecordingLiveActivityContent?) async {
        record(.end(final: content))
    }

    private func record(_ call: Call) {
        lock.withLock { _calls.append(call) }
    }
}

/// The 5 s rhythm of the Live Activity, driven by the test.
final class ManualTicks: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [AsyncStream<Void>.Continuation] = []

    func stream() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        lock.withLock { continuations.append(continuation) }
        return stream
    }

    /// Five seconds pass.
    func tick() {
        let current = lock.withLock { continuations }
        for continuation in current {
            continuation.yield()
        }
    }
}
