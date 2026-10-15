import Foundation
@testable import StravaClone

/// Fake `MotionActivityProvider`: answers the authorization with `isAuthorized`, readings
/// driven by `send(_:)`.
@MainActor
final class FakeMotionActivityProvider: MotionActivityProvider {
    var isAuthorized = true
    private(set) var authorizationRequests = 0

    private lazy var broadcaster = LocationBroadcaster<MotionReading> { _ in }

    var subscriberCount: Int { broadcaster.subscriberCount }

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        return isAuthorized
    }

    func readings() async -> AsyncStream<MotionReading> {
        broadcaster.subscribe(replaysLatest: false, bufferingPolicy: .unbounded)
    }

    func send(_ reading: MotionReading) {
        broadcaster.send(reading)
    }
}

/// Counts the haptics of the automatic Pause.
@MainActor
final class FakeAutoPauseFeedback: AutoPauseFeedback {
    enum Event: Equatable {
        case started, ended
    }

    private(set) var events: [Event] = []

    func autoPauseStarted() async {
        events.append(.started)
    }

    func autoPauseEnded() async {
        events.append(.ended)
    }
}
