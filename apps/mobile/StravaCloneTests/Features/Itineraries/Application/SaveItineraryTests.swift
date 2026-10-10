import Foundation
import Testing
@testable import StravaClone

/// Saving writes the detail straight to the cache (ADR-030 §8), so the Itinerary is listed
/// at once; a failed save leaves the cache as it was.
struct SaveItineraryTests {
    private let creation = ItineraryCreation(
        id: .fixture(1),
        name: "Tour du lac",
        sport: .hike,
        waypoints: [Coordinate(latitude: 45.9, longitude: 6.12), Coordinate(latitude: 45.92, longitude: 6.12)],
        legs: [.straight]
    )

    @Test func aSavedItineraryIsListedAtOnceWithItsDetail() async throws {
        let repository = FakeItineraryRepository()
        let cache = GRDBItineraryCache(database: try AppDatabase.inMemory())
        let detail = ItineraryDetail.fixture(1, name: "Tour du lac")
        repository.createResults = [.success(detail)]

        let saved = try await SaveItinerary(repository: repository, cache: cache)(creation)

        #expect(saved == detail)
        #expect(repository.creations == [creation])
        let summaries = try await cache.summaries(limit: 20)
        #expect(summaries.map(\.id) == [.fixture(1)])
        #expect(summaries.first?.name == "Tour du lac")
        // Thumbnail until the next resync brings the server's: the saved track at precision 5.
        #expect(summaries.first?.mapPolyline == EncodedPolyline(encoding: detail.track.polyline.decode()))
        #expect(try await cache.detail(id: .fixture(1)) == detail)
    }

    @Test func aFailedSaveLeavesTheCacheUntouched() async throws {
        let repository = FakeItineraryRepository()
        let cache = GRDBItineraryCache(database: try AppDatabase.inMemory())
        repository.createResults = [.failure(.unavailable)]

        await #expect(throws: ItineraryError.unavailable) {
            try await SaveItinerary(repository: repository, cache: cache)(creation)
        }
        #expect(try await cache.summaries(limit: 20).isEmpty)
    }
}

struct ItineraryTrackThumbnailTests {
    @Test func aShortTrackKeepsEveryPoint() {
        let points = [Coordinate(latitude: 45.9, longitude: 6.12), Coordinate(latitude: 45.95, longitude: 6.2)]
        let track = ItineraryTrack(polyline: EncodedPolyline(encoding: points, precision: 6), altitudes: [400, 500])

        #expect(track.mapPolyline() == EncodedPolyline(value: "_zcwG_ijd@owH_sN"))
    }

    @Test func aLongTrackIsThinnedToTheMapPolylineLimitKeepingItsEnds() {
        let points = (0 ..< 5_000).map { Coordinate(latitude: 45 + Double($0) * 0.000_18, longitude: 6 + sin(Double($0)) * 0.01) }
        let track = ItineraryTrack(polyline: EncodedPolyline(encoding: points, precision: 6), altitudes: points.map { _ in 0 })

        let thumbnail = track.mapPolyline()
        let decoded = thumbnail.decode()

        #expect(thumbnail.value.count <= 2_000)
        #expect(decoded.count > 100)
        #expect(decoded.first == Coordinate(latitude: 45, longitude: 6))
        #expect(decoded.last == Coordinate(latitude: 45.89982, longitude: 5.99336))
    }
}
