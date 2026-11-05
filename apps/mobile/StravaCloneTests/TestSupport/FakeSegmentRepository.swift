import Foundation
@testable import StravaClone

/// In-memory `SegmentRepository` (ADR-025 §3): scripted answers and recorded calls.
final class FakeSegmentRepository: SegmentRepository, @unchecked Sendable {
    enum Call: Equatable {
        case sheet(String)
        case leaderboard(String, LeaderboardSelection, cursor: String?)
        case setStarred(String, Bool)
        case rename(String, String)
        case delete(String)
    }

    private let lock = NSLock()

    var sheetResult: Result<SegmentSheet, SegmentError> = .success(.sample())
    /// Answers by cursor; `nil` is the first page.
    var leaderboardResults: [String?: Result<Leaderboard, SegmentError>] = [nil: .success(.sample())]
    var starResult: Result<Void, SegmentError> = .success(())
    var renameResult: Result<Void, SegmentError> = .success(())
    var deleteResult: Result<Void, SegmentError> = .success(())

    private(set) var calls: [Call] = []

    func sheet(id: String) async throws(SegmentError) -> SegmentSheet {
        try lock.withLock {
            calls.append(.sheet(id))
            return sheetResult
        }.get()
    }

    func leaderboard(id: String, selection: LeaderboardSelection, cursor: String?) async throws(SegmentError) -> Leaderboard {
        try lock.withLock {
            calls.append(.leaderboard(id, selection, cursor: cursor))
            return leaderboardResults[cursor] ?? .failure(.server)
        }.get()
    }

    func setStarred(id: String, _ starred: Bool) async throws(SegmentError) {
        try lock.withLock {
            calls.append(.setStarred(id, starred))
            return starResult
        }.get()
    }

    func rename(id: String, to name: String) async throws(SegmentError) {
        try lock.withLock {
            calls.append(.rename(id, name))
            return renameResult
        }.get()
    }

    func delete(id: String) async throws(SegmentError) {
        try lock.withLock {
            calls.append(.delete(id))
            return deleteResult
        }.get()
    }
}

extension ActivityAuthor {
    static func athlete(_ id: String) -> ActivityAuthor {
        ActivityAuthor(id: id, displayName: "Athlète \(id)", avatarURL: nil)
    }
}

extension LeaderboardEntry {
    static func line(_ rank: Int, _ athlete: String, seconds: Int = 300) -> LeaderboardEntry {
        LeaderboardEntry(
            rank: rank,
            athlete: .athlete(athlete),
            effortID: "effort-\(athlete)",
            activityID: "activity-\(athlete)",
            elapsedSeconds: seconds,
            startedAt: Date(timeIntervalSince1970: 1_780_000_000)
        )
    }
}

extension Leaderboard {
    static func sample(
        limited: Bool = true,
        entries: [LeaderboardEntry] = [.line(1, "ann"), .line(2, "bob")],
        me: LeaderboardEntry? = nil,
        athleteCount: Int = 2,
        nextCursor: String? = nil
    ) -> Leaderboard {
        Leaderboard(
            limited: limited,
            entries: entries,
            me: me,
            localLegend: LocalLegend(holder: nil, myEffortCount: 0),
            athleteCount: athleteCount,
            nextCursor: nextCursor
        )
    }
}

extension SegmentSheet {
    static func sample(
        id: String = "seg-1",
        isStarred: Bool = false,
        favoriteCount: Int = 3,
        isMine: Bool = false,
        canDelete: Bool = false
    ) -> SegmentSheet {
        SegmentSheet(
            id: id,
            name: "Col du test",
            sport: SportType(code: "ride"),
            isVerified: false,
            distance: Distance(meters: 1_200),
            elevationGain: 100,
            averageGrade: 8.3,
            climbCategory: .four,
            track: SegmentTrack(polyline: EncodedPolyline(value: "", precision: 6), altitudes: []),
            isStarred: isStarred,
            favoriteCount: favoriteCount,
            isMine: isMine,
            canDelete: canDelete,
            isMatchingHistory: false,
            myEfforts: [],
            myRecord: nil,
            localLegend: LocalLegend(holder: nil, myEffortCount: 0),
            leaderboard: .sample()
        )
    }
}
