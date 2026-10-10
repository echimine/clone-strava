import Foundation
@testable import StravaClone

/// Hand-written `AnalyticsClient` (ADR-025 §3): records every event captured, in order.
final class FakeAnalyticsClient: AnalyticsClient, @unchecked Sendable {
    private let captured = Locked<[AnalyticsEvent]>([])

    var events: [AnalyticsEvent] { captured.value }

    var names: [String] { events.map(\.name) }

    func capture(_ event: AnalyticsEvent) {
        captured.value.append(event)
    }

    /// Events with this name, oldest first.
    func events(named name: String) -> [AnalyticsEvent] {
        events.filter { $0.name == name }
    }
}
