import Foundation

/// The one sign-out confirmation (ADR-031 §10, §14, ADR-030 §8, ADR-037 §6), composed by the
/// app shell since it spans features: the Recording in progress, the Activities not yet sent
/// (`recorded`, `created`, `trace_uploaded`, `failed`; one in `processing` is safe on the
/// server), the Media not yet sent and the Itinerary changes not yet sent. `nil` when nothing
/// would be lost.
enum SignOutWarning {
    static func message(recordingInProgress: Bool, unsentActivities: Int, unsentMedia: Int, pendingItineraryChanges: Int) -> String? {
        let lines = [
            recordingInProgress ? RecordingMessages.signOutWarning : nil,
            unsent(activities: unsentActivities, media: unsentMedia),
            ItineraryMessages.signOutWarning(pendingChanges: pendingItineraryChanges),
        ].compactMap { $0 }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// "2 activités et 3 médias pas encore envoyés seront perdus.": alone, each kind agrees with
    /// its noun; together they take the masculine plural.
    private static func unsent(activities: Int, media: Int) -> String? {
        let activityCount = activities == 1 ? "1 activité" : "\(activities) activités"
        let mediaCount = media == 1 ? "1 média" : "\(media) médias"
        switch (activities > 0, media > 0) {
        case (false, false):
            return nil
        case (true, true):
            return "\(activityCount) et \(mediaCount) pas encore envoyés seront perdus."
        case (true, false):
            return activities == 1 ? "1 activité pas encore envoyée sera perdue." : "\(activityCount) pas encore envoyées seront perdues."
        case (false, true):
            return media == 1 ? "1 média pas encore envoyé sera perdu." : "\(mediaCount) pas encore envoyés seront perdus."
        }
    }
}
