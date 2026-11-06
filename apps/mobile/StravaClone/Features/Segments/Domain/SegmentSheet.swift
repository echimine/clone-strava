import Foundation

/// A Segment's path, every point as polyline6 with one altitude per point (`GET /v1/segments/:id`).
struct SegmentTrack: Equatable, Sendable {
    let polyline: EncodedPolyline
    let altitudes: [Double]

    var coordinates: [Coordinate] { polyline.decode() }

    /// The same profile as an Itinerary's (ADR-030 §3), from the path and its altitudes.
    var elevationProfile: ElevationProfile {
        ElevationProfile(coordinates: coordinates, altitudes: altitudes)
    }
}

/// One of my Efforts on the sheet, whatever the visibility of its Activity (ADR-039 §15).
struct MySegmentEffort: Identifiable, Equatable, Sendable {
    let id: String
    let activityID: String
    let isPublicActivity: Bool
    let startedAt: Date
    let elapsedSeconds: Int
    let medal: Medal?
    /// False: « Privée · hors Classement » (not public, in my privacy zone, or rejected).
    let standing: Bool
    /// The Effort that forms my line in Tous; only it shows my rank.
    let isLeaderboardLine: Bool
    let rank: Int?
}

/// One line of a Leaderboard: an athlete's best Effort that stands (ADR-039 §8).
struct LeaderboardEntry: Identifiable, Equatable, Sendable {
    let rank: Int
    let athlete: ActivityAuthor
    let effortID: String
    let activityID: String
    let elapsedSeconds: Int
    let startedAt: Date

    var id: String { effortID }
}

/// The Local Legend for the sex chip, and my own count over the same 90 days in that sex
/// (ADR-039 §8): nil when I am not of that sex.
struct LocalLegend: Equatable, Sendable {
    struct Holder: Equatable, Sendable {
        let athlete: ActivityAuthor
        let effortCount: Int
    }

    let holder: Holder?
    let myEffortCount: Int?

    /// « Encore k pour devenir Légende locale »: nil when nobody holds it, when I do, or when I am
    /// not of its sex.
    func effortsToTakeIt(viewerID: String) -> Int? {
        guard let holder, let myEffortCount, holder.athlete.id != viewerID else { return nil }
        return holder.effortCount - myEffortCount + 1
    }
}

/// `GET /v1/segments/:id/leaderboard` (ADR-039 §8, §9). `limited`: without Premium, the top 10
/// of Tous only. `me` is my line in this filter, nil when I am not in it.
struct Leaderboard: Equatable, Sendable {
    let limited: Bool
    var entries: [LeaderboardEntry]
    let me: LeaderboardEntry?
    let localLegend: LocalLegend
    /// Athletes with an Effort that stands on the Segment, in Tous.
    let athleteCount: Int
    var nextCursor: String?

    /// My line pinned under the list, unless it is already in it (ADR-039 §9: no duplicate).
    var pinnedMe: LeaderboardEntry? {
        guard let me, !entries.contains(where: { $0.effortID == me.effortID }) else { return nil }
        return me
    }

    func isMine(_ entry: LeaderboardEntry) -> Bool { entry.effortID == me?.effortID }
}

/// `GET /v1/segments/:id` (ADR-039 §12): free for everyone. The creator is never shown.
struct SegmentSheet: Equatable, Sendable {
    let id: String
    var name: String
    let sport: SportType
    let isVerified: Bool
    let distance: Distance
    let elevationGain: Double?
    let averageGrade: Double?
    let climbCategory: ClimbCategory?
    let track: SegmentTrack
    var isFavorite: Bool
    var favoriteCount: Int
    let isMine: Bool
    /// The creator may delete it while nobody else has an Effort on it.
    let canDelete: Bool
    /// « Recherche des Efforts passés sur ce Segment… »
    let isMatchingHistory: Bool
    /// Every Effort of mine, newest first.
    let myEfforts: [MySegmentEffort]
    let myRecord: MySegmentEffort?
    let localLegend: LocalLegend
    /// The top 10 of Tous and my line.
    let leaderboard: Leaderboard

    /// « Mon rang » in Tous, everywhere and free.
    var myRank: Int? { leaderboard.me?.rank }
}
