import Foundation

/// `AutoPausePreferences` in `UserDefaults`, one key per sport.
extension UserDefaultsRecordingPreferences: AutoPausePreferences {
    private static func autoPauseKey(_ sport: RecordingSport) -> String {
        "recording.autoPause.\(sport.rawValue)"
    }

    func autoPause(for sport: RecordingSport) -> Bool? {
        defaults.object(forKey: Self.autoPauseKey(sport)) as? Bool
    }

    func rememberAutoPause(_ enabled: Bool, for sport: RecordingSport) {
        defaults.set(enabled, forKey: Self.autoPauseKey(sport))
    }
}
