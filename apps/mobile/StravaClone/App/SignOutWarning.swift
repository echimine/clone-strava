import Foundation

/// The one sign-out confirmation (ADR-031 §10, §14, ADR-030 §8), composed by the app shell
/// since it spans features: the Recording in progress, the Activities not yet sent (`recorded`,
/// `created`, `trace_uploaded`, `failed`; one in `processing` is safe on the server) and the
/// Itinerary changes not yet sent. `nil` when nothing would be lost.
enum SignOutWarning {
    static func message(recordingInProgress: Bool, unsentActivities: Int, pendingItineraryChanges: Int) -> String? {
        let lines = [
            recordingInProgress ? RecordingMessages.signOutWarning : nil,
            activities(unsentActivities),
            ItineraryMessages.signOutWarning(pendingChanges: pendingItineraryChanges),
        ].compactMap { $0 }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private static func activities(_ count: Int) -> String? {
        switch count {
        case ...0: nil
        case 1: "1 activité pas encore envoyée sera perdue."
        default: "\(count) activités pas encore envoyées seront perdues."
        }
    }
}
