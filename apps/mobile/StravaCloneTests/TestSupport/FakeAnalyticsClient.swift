import Foundation
@testable import StravaClone

/// Hand-written `AnalyticsClient` (ADR-025 §3): records every event sent, in order, and the
/// identity calls apart (`calls`).
final class FakeAnalyticsClient: AnalyticsClient, @unchecked Sendable {
    enum Call: Equatable {
        case reset
        case identify(userId: String)
    }

    private let captured = Locked<[AnalyticsEvent]>([])
    private let recordedCalls = Locked<[Call]>([])

    var events: [AnalyticsEvent] { captured.value }

    var names: [String] { events.map(\.name) }

    /// `identify(userId:)` and `reset()`, oldest first.
    var calls: [Call] { recordedCalls.value }

    func capture(_ event: AnalyticsEvent) {
        captured.value.append(event)
    }

    func identify(userId: String) { recordedCalls.value.append(.identify(userId: userId)) }
    func reset() { recordedCalls.value.append(.reset) }

    /// Events with this name, oldest first.
    func events(named name: String) -> [AnalyticsEvent] {
        events.filter { $0.name == name }
    }
}
