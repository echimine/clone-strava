import Foundation

/// `APIClient` adapter of `SegmentRepository`: `GET /v1/segments/:id` and its `leaderboard`
/// (ADR-039 §12), on the types generated from openapi.json (ADR-026 §5); « Renommer »,
/// « Supprimer » and the star call the endpoints of spec #249.
struct APISegmentRepository: SegmentRepository {
    private typealias SheetResponse = Components.Schemas.SegmentSheetDto_Output
    private typealias LeaderboardResponse = Components.Schemas.LeaderboardResponseDto_Output

    private struct RenameBody: Encodable { let name: String }
    /// `PATCH /v1/segments/:id` answers the Segment's id and name.
    private struct RenameResponse: Decodable { let id: String }

    private struct ErrorEnvelope: Decodable {
        struct Body: Decodable { let code: String }
        let error: Body
    }

    let apiClient: APIClient
    /// The viewer's time zone, for the calendar periods (ADR-039 §8).
    var timeZone: @Sendable () -> TimeZone = { .current }

    func sheet(id: String) async throws(SegmentError) -> SegmentSheet {
        let response: SheetResponse = try await call { () async throws(APIError) in
            try await apiClient.get("/v1/segments/\(id)")
        }
        return response.model
    }

    func leaderboard(id: String, selection: LeaderboardSelection, cursor: String?) async throws(SegmentError) -> Leaderboard {
        var query = [URLQueryItem(name: "gender", value: selection.gender.rawValue)]
        if let filter = selection.filter?.query {
            query.append(URLQueryItem(name: "filter", value: filter.filter))
            if let value = filter.value {
                query.append(URLQueryItem(name: "value", value: value))
            }
            if filter.filter == "period" {
                query.append(URLQueryItem(name: "tz", value: timeZone().identifier))
            }
        }
        if let cursor {
            query.append(URLQueryItem(name: "cursor", value: cursor))
        }
        let response: LeaderboardResponse = try await call { () async throws(APIError) in
            try await apiClient.get("/v1/segments/\(id)/leaderboard", query: query)
        }
        return response.model
    }

    func setStarred(id: String, _ starred: Bool) async throws(SegmentError) {
        let _: NoContent = try await call { () async throws(APIError) in
            try await apiClient.send(method: starred ? "PUT" : "DELETE", path: "/v1/segments/\(id)/favorite")
        }
    }

    func rename(id: String, to name: String) async throws(SegmentError) {
        let _: RenameResponse = try await call { () async throws(APIError) in
            try await apiClient.send(method: "PATCH", path: "/v1/segments/\(id)", body: RenameBody(name: name))
        }
    }

    func delete(id: String) async throws(SegmentError) {
        let _: NoContent = try await call { () async throws(APIError) in
            try await apiClient.send(method: "DELETE", path: "/v1/segments/\(id)")
        }
    }

    private func call<T>(_ operation: () async throws(APIError) -> T) async throws(SegmentError) -> T {
        do {
            return try await operation()
        } catch {
            switch error {
            case .offline: throw .offline
            case .unauthorized: throw .unauthorized
            case .http(let status, let body):
                let code = body.flatMap { try? JSONDecoder().decode(ErrorEnvelope.self, from: $0) }?.error.code
                switch (status, code) {
                case (404, _): throw .notFound
                case (403, "premium_required"): throw .premiumRequired
                case (409, "has_other_efforts"): throw .hasOtherEfforts
                case (400 ..< 500, _): throw .invalid(code: code)
                default: throw .server
                }
            case .decoding: throw .server
            case .transport: throw .network
            }
        }
    }
}

// MARK: - Generated types → domain

private func author(id: String, displayName: String, avatarUrl: String?) -> ActivityAuthor {
    ActivityAuthor(id: id, displayName: displayName, avatarUrl: avatarUrl)
}

private extension Components.Schemas.SegmentSheetDto_Output {
    var model: SegmentSheet {
        let legend = LocalLegend(
            holder: localLegend.legend.map {
                .init(
                    athlete: author(id: $0.athlete.id, displayName: $0.athlete.displayName, avatarUrl: $0.athlete.avatarUrl),
                    effortCount: $0.effortCount
                )
            },
            myEffortCount: localLegend.myEffortCount
        )
        return SegmentSheet(
            id: id,
            name: name,
            sport: SportType(code: sportTypeCode),
            isVerified: verified,
            distance: Distance(meters: distanceM),
            elevationGain: elevationGainM,
            averageGrade: avgGrade,
            climbCategory: climbCategory.flatMap { ClimbCategory(rawValue: $0.rawValue) },
            track: SegmentTrack(polyline: EncodedPolyline(value: track.polyline6, precision: 6), altitudes: track.altitudesM),
            isStarred: starred,
            favoriteCount: favoriteCount,
            isMine: isMine,
            canDelete: canDelete,
            isMatchingHistory: historyMatching,
            myEfforts: myEfforts.map {
                MySegmentEffort(
                    id: $0.id,
                    activityID: $0.activityId,
                    isPublicActivity: $0.activityVisibility == ._public,
                    startedAt: $0.startedAt,
                    elapsedSeconds: $0.elapsedTimeS,
                    medal: $0.medal.flatMap { Medal(rawValue: $0.rawValue) },
                    standing: $0.standing,
                    isLeaderboardLine: $0.isLeaderboardLine,
                    rank: $0.rank
                )
            },
            myRecord: myRecord.map {
                MySegmentEffort(
                    id: $0.id,
                    activityID: $0.activityId,
                    isPublicActivity: $0.activityVisibility == ._public,
                    startedAt: $0.startedAt,
                    elapsedSeconds: $0.elapsedTimeS,
                    medal: $0.medal.flatMap { Medal(rawValue: $0.rawValue) },
                    standing: $0.standing,
                    isLeaderboardLine: $0.isLeaderboardLine,
                    rank: $0.rank
                )
            },
            localLegend: legend,
            leaderboard: Leaderboard(
                limited: leaderboard.limited,
                entries: leaderboard.entries.map {
                    LeaderboardEntry(
                        rank: $0.rank,
                        athlete: author(id: $0.athlete.id, displayName: $0.athlete.displayName, avatarUrl: $0.athlete.avatarUrl),
                        effortID: $0.effortId,
                        activityID: $0.activityId,
                        elapsedSeconds: $0.elapsedTimeS,
                        startedAt: $0.startedAt
                    )
                },
                me: leaderboard.me.map {
                    LeaderboardEntry(
                        rank: $0.rank,
                        athlete: author(id: $0.athlete.id, displayName: $0.athlete.displayName, avatarUrl: $0.athlete.avatarUrl),
                        effortID: $0.effortId,
                        activityID: $0.activityId,
                        elapsedSeconds: $0.elapsedTimeS,
                        startedAt: $0.startedAt
                    )
                },
                localLegend: LocalLegend(
                    holder: leaderboard.localLegend.legend.map {
                        .init(
                            athlete: author(id: $0.athlete.id, displayName: $0.athlete.displayName, avatarUrl: $0.athlete.avatarUrl),
                            effortCount: $0.effortCount
                        )
                    },
                    myEffortCount: leaderboard.localLegend.myEffortCount
                ),
                athleteCount: leaderboard.athleteCount,
                nextCursor: leaderboard.nextCursor
            )
        )
    }
}

private extension Components.Schemas.LeaderboardResponseDto_Output {
    var model: Leaderboard {
        Leaderboard(
            limited: limited,
            entries: entries.map {
                LeaderboardEntry(
                    rank: $0.rank,
                    athlete: author(id: $0.athlete.id, displayName: $0.athlete.displayName, avatarUrl: $0.athlete.avatarUrl),
                    effortID: $0.effortId,
                    activityID: $0.activityId,
                    elapsedSeconds: $0.elapsedTimeS,
                    startedAt: $0.startedAt
                )
            },
            me: me.map {
                LeaderboardEntry(
                    rank: $0.rank,
                    athlete: author(id: $0.athlete.id, displayName: $0.athlete.displayName, avatarUrl: $0.athlete.avatarUrl),
                    effortID: $0.effortId,
                    activityID: $0.activityId,
                    elapsedSeconds: $0.elapsedTimeS,
                    startedAt: $0.startedAt
                )
            },
            localLegend: LocalLegend(
                holder: localLegend.legend.map {
                    .init(
                        athlete: author(id: $0.athlete.id, displayName: $0.athlete.displayName, avatarUrl: $0.athlete.avatarUrl),
                        effortCount: $0.effortCount
                    )
                },
                myEffortCount: localLegend.myEffortCount
            ),
            athleteCount: athleteCount,
            nextCursor: nextCursor
        )
    }
}
