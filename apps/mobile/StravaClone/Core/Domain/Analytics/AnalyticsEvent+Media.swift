import Foundation

/// Property values of the Media events (ADR-037 §13), mirrored in
/// `packages/contracts/src/analytics/catalog.ts` (`APP_ANALYTICS_EVENTS`).
extension AnalyticsEvent {
    /// Which screen opened the full-screen viewer.
    enum MediaViewerSource: String, Sendable {
        case feed
        /// My Activités tab, or another athlete's.
        case profileActivities = "profile_activities"
        case detail
        case gallery
    }

    /// The screen that saved the Media of `activity_media_saved`.
    enum ActivityMediaSavedEntry: String, Sendable {
        /// The Recording's finish screen (#185).
        case recording
        /// "Modifier".
        case edit
    }
}
