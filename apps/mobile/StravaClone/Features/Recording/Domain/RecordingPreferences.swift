import Foundation

/// Recording choices kept on the device (ADR-031 §2).
protocol RecordingPreferences: Sendable {
    /// Sport of the last saved Recording, preselected on the pre-start screen (`run` without one).
    var lastSavedSport: RecordingSport? { get }
    /// Called when a Recording is saved.
    func rememberSavedSport(_ sport: RecordingSport)
}
