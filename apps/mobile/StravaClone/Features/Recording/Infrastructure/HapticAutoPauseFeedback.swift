import AudioToolbox
import UIKit

/// `AutoPauseFeedback` (ADR-031 §4): a notification haptic in the foreground; with the screen
/// locked, the system vibration is attempted, with no fallback notification.
@MainActor
final class HapticAutoPauseFeedback: AutoPauseFeedback {
    private let generator = UINotificationFeedbackGenerator()

    func autoPauseStarted() async {
        play(.warning)
    }

    func autoPauseEnded() async {
        play(.success)
    }

    private func play(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        if UIApplication.shared.applicationState == .active {
            generator.notificationOccurred(type)
        } else {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }
}
