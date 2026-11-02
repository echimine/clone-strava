import Foundation

/// What iOS says about the notification permission (ADR-035 §7). Provisional or ephemeral
/// authorization counts as `granted`: the question has been settled.
enum NotificationAuthorization: Equatable, Sendable {
    /// iOS has not shown its one-time prompt yet.
    case notDetermined
    case granted
    case denied
}

/// The notification permission, and nothing else (ADR-035 §7): authorization only (alert, sound,
/// badge), no APNs registration and no token, no provisional authorization. Real push
/// notifications come later (ADR-006, ADR-011).
protocol NotificationPermission: Sendable {
    func status() async -> NotificationAuthorization
    /// Shows iOS's one-time prompt; returns whether the person allowed notifications.
    func requestAuthorization() async -> Bool
}

/// For previews and the tests that are not about the step: the permission is already settled,
/// so the priming screen is skipped.
struct SettledNotificationPermission: NotificationPermission {
    func status() async -> NotificationAuthorization { .denied }
    func requestAuthorization() async -> Bool { false }
}
