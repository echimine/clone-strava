import Foundation
@testable import StravaClone

/// Fake `NotificationPermission` (ADR-025 §3): answers with the status and the system prompt's
/// answer set per test, and counts the prompts asked for.
final class FakeNotificationPermission: NotificationPermission, @unchecked Sendable {
    private let current: Locked<NotificationAuthorization>
    /// What the person answers on the system prompt.
    let answer: Bool
    private let requests = Locked(0)

    init(status: NotificationAuthorization, answer: Bool = true) {
        current = Locked(status)
        self.answer = answer
    }

    var requestCount: Int { requests.value }

    func status() async -> NotificationAuthorization {
        current.value
    }

    func requestAuthorization() async -> Bool {
        requests.value += 1
        current.value = answer ? .granted : .denied
        return answer
    }
}
