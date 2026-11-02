import Foundation
@testable import StravaClone

/// Hand-written `AnalyticsClient` (ADR-025 §3): records every event sent, in order, and the
/// consent and identity calls apart (`calls`). Like the SDK, it sends nothing between `optOut()`
/// and the next `optIn()` (ADR-035 §8); it starts opted in.
final class FakeAnalyticsClient: AnalyticsClient, @unchecked Sendable {
    enum Call: Equatable {
        case optIn, optOut, reset
        case identify(userId: String)
    }

    private let captured = Locked<[AnalyticsEvent]>([])
    private let recordedCalls = Locked<[Call]>([])
    private let isOptedIn = Locked(true)

    var events: [AnalyticsEvent] { captured.value }

    var names: [String] { events.map(\.name) }

    /// `optIn()`, `optOut()`, `identify(userId:)` and `reset()`, oldest first.
    var calls: [Call] { recordedCalls.value }

    func capture(_ event: AnalyticsEvent) {
        guard isOptedIn.value else { return }
        captured.value.append(event)
    }

    func optIn() {
        isOptedIn.value = true
        recordedCalls.value.append(.optIn)
    }

    func optOut() {
        isOptedIn.value = false
        recordedCalls.value.append(.optOut)
    }
    func identify(userId: String) { recordedCalls.value.append(.identify(userId: userId)) }
    func reset() { recordedCalls.value.append(.reset) }

    /// Events with this name, oldest first.
    func events(named name: String) -> [AnalyticsEvent] {
        events.filter { $0.name == name }
    }
}
