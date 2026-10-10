import Foundation
@testable import StravaClone

extension ItineraryID {
    /// Stable ids for readable expectations: `.fixture(1)` is `00000000-0000-4000-8000-000000000001`.
    static func fixture(_ number: Int) -> ItineraryID {
        ItineraryID(String(format: "00000000-0000-4000-8000-%012d", number))!
    }
}

extension Date {
    /// `2026-10-10T08:00:00.500Z` plus `minutes`: milliseconds like the API, exact in binary.
    static func fixture(minutes: Double = 0) -> Date {
        Date(timeIntervalSince1970: 1_791_619_200 + minutes * 60 + 0.5)
    }
}

extension ItinerarySummary {
    static func fixture(
        _ number: Int,
        name: String? = nil,
        sport: SportType = .run,
        distance: Double = 10_000,
        elevationGain: Double = 120,
        mapPolyline: String = "_p~iF~ps|U_ulLnnqC",
        updatedMinutes: Double = 0
    ) -> ItinerarySummary {
        ItinerarySummary(
            id: .fixture(number),
            name: name ?? "Itinéraire \(number)",
            sport: sport,
            distance: Distance(meters: distance),
            elevationGain: elevationGain,
            mapPolyline: EncodedPolyline(value: mapPolyline),
            updatedAt: .fixture(minutes: updatedMinutes)
        )
    }
}

extension ItineraryDetail {
    static func fixture(
        _ number: Int,
        name: String? = nil,
        sport: SportType = .hike,
        elevationSource: ElevationSource = .ign,
        updatedMinutes: Double = 0
    ) -> ItineraryDetail {
        ItineraryDetail(
            id: .fixture(number),
            name: name ?? "Itinéraire \(number)",
            sport: sport,
            distance: Distance(meters: 2_224),
            elevationGain: 87.5,
            elevationSource: elevationSource,
            track: ItineraryTrack(
                polyline: EncodedPolyline(
                    encoding: [
                        Coordinate(latitude: 45.9, longitude: 6.12),
                        Coordinate(latitude: 45.91, longitude: 6.12),
                        Coordinate(latitude: 45.92, longitude: 6.12),
                    ],
                    precision: 6
                ),
                altitudes: [446.5, 480, 534]
            ),
            createdAt: .fixture(minutes: -60),
            updatedAt: .fixture(minutes: updatedMinutes)
        )
    }
}

extension CreatedItinerary {
    /// `201`: the Itinerary did not exist yet.
    static func new(_ detail: ItineraryDetail) -> CreatedItinerary {
        CreatedItinerary(detail: detail, isReplay: false)
    }

    /// `200`: an earlier try was stored, its answer lost.
    static func replay(_ detail: ItineraryDetail) -> CreatedItinerary {
        CreatedItinerary(detail: detail, isReplay: true)
    }
}
