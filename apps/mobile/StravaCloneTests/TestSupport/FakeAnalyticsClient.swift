import Foundation
@testable import StravaClone

/// Hand-written `AnalyticsClient` (ADR-025 §3): records every event captured, in order, and the
/// consent and identity calls apart (`calls`).
final class FakeAnalyticsClient: AnalyticsClient, @unchecked Sendable {
    enum Call: Equatable {
        case optIn, optOut, reset
        case identify(userId: String)
    }

    private let captured = Locked<[AnalyticsEvent]>([])
    private let recordedCalls = Locked<[Call]>([])

    var events: [AnalyticsEvent] { captured.value }

    var names: [String] { events.map(\.name) }

    /// `optIn()`, `optOut()`, `identify(userId:)` and `reset()`, oldest first.
    var calls: [Call] { recordedCalls.value }

    func capture(_ event: AnalyticsEvent) {
        captured.value.append(event)
    }

    func optIn() { recordedCalls.value.append(.optIn) }
    func optOut() { recordedCalls.value.append(.optOut) }
    func identify(userId: String) { recordedCalls.value.append(.identify(userId: userId)) }
    func reset() { recordedCalls.value.append(.reset) }

    /// Events with this name, oldest first.
    func events(named name: String) -> [AnalyticsEvent] {
        events.filter { $0.name == name }
    }
}
