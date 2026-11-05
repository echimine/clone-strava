import Foundation

/// `APIClient` adapter of `ActivityResultsRepository` (ADR-039 §12): « Résultats » of a visible
/// Activity, and the author's removal of a Best effort, decoded with the generated OpenAPI
/// types (ADR-026).
struct APIActivityResultsRepository: ActivityResultsRepository {
    private typealias ResultsResponse = Components.Schemas.ActivityResultsDto_Output

    let apiClient: APIClient

    func results(of id: ActivityID) async throws(ActivityDetailError) -> ActivityResults {
        do {
            let response: ResultsResponse = try await apiClient.get("/v1/activities/\(id)/results")
            return response.model
        } catch {
            throw ActivityDetailError(error)
        }
    }

    func removeBestEffort(of id: ActivityID, distanceM: Double) async throws(ActivityDetailError) {
        do {
            let _: NoContent = try await apiClient.send(
                method: "DELETE",
                path: "/v1/activities/\(id)/best-efforts/\(Self.pathComponent(distanceM))"
            )
        } catch {
            throw ActivityDetailError(error)
        }
    }

    /// « 1000 », « 21097.5 »: what `ParseFloatPipe` reads.
    static func pathComponent(_ distanceM: Double) -> String {
        distanceM == distanceM.rounded() ? String(Int(distanceM)) : String(distanceM)
    }
}

private extension Components.Schemas.ActivityResultsDto_Output {
    var model: ActivityResults {
        ActivityResults(
            matchingInProgress: matchingInProgress,
            poolLength: poolLengthM.map { Distance(meters: $0) },
            bestEfforts: bestEfforts.map {
                BestEffortResult(
                    distanceM: $0.distanceM,
                    elapsedTime: .milliseconds($0.elapsedTimeMs),
                    medal: $0.medal.flatMap { Medal(rawValue: $0.rawValue) },
                    isFirst: $0.isFirst,
                    isCurrentRecord: $0.isCurrentRecord,
                    removable: $0.removable
                )
            },
            efforts: efforts.map {
                SegmentEffortResult(
                    id: $0.id,
                    segmentID: $0.segment.id,
                    segmentName: $0.segment.name,
                    segmentDistance: Distance(meters: $0.segment.distanceM),
                    verified: $0.segment.verified,
                    elapsedTime: .seconds($0.elapsedTimeS),
                    medal: $0.medal.flatMap { Medal(rawValue: $0.rawValue) },
                    isFirstPass: $0.isFirstPass,
                    localLegend: $0.localLegend,
                    startPoint: Coordinate(latitude: $0.startPoint.lat, longitude: $0.startPoint.lon)
                )
            }
        )
    }
}
