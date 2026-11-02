import UserNotifications

/// `NotificationPermission` over `UNUserNotificationCenter` (ADR-035 §7): alert, sound and badge,
/// never `.provisional`, and no `registerForRemoteNotifications()`.
struct UserNotificationsPermission: NotificationPermission {
    func status() async -> NotificationAuthorization {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized, .provisional, .ephemeral: .granted
        @unknown default: .denied
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
}
