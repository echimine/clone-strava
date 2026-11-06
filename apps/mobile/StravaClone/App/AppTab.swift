import Foundation

/// Tabs of the signed-in app; Save brings the athlete back to the feed (ADR-031 §11).
enum AppTab: Hashable {
    case feed, map, record, profile
}
