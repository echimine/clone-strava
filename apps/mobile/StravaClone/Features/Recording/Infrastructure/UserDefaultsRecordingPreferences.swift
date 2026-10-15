import Foundation

/// `RecordingPreferences` in `UserDefaults`.
struct UserDefaultsRecordingPreferences: RecordingPreferences, @unchecked Sendable {
    private static let lastSavedSportKey = "recording.lastSavedSport"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var lastSavedSport: RecordingSport? {
        defaults.string(forKey: Self.lastSavedSportKey).flatMap(RecordingSport.init(rawValue:))
    }

    func rememberSavedSport(_ sport: RecordingSport) {
        defaults.set(sport.rawValue, forKey: Self.lastSavedSportKey)
    }
}
