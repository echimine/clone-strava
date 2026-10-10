import Foundation
import Testing
@testable import StravaClone

/// "Modifier" reopens a saved Itinerary in the editor as it was stored (ADR-030 §5): Waypoints,
/// Legs and modes as they were, with nothing left to route.
@MainActor
struct ItineraryDraftRestoringTests {
    private let a = Coordinate(latitude: 45.900, longitude: 6.120)
    private let corner = Coordinate(latitude: 45.900, longitude: 6.121)
    private let b = Coordinate(latitude: 45.901, longitude: 6.121)
    private let c = Coordinate(latitude: 45.910, longitude: 6.121)

    private var saved: SavedItinerary {
        SavedItinerary(
            id: .fixture(7),
            name: "Tour du lac",
            sport: .ride,
            waypoints: [a, b, c],
            legs: [.follow(EncodedPolyline(encoding: [a, corner, b], precision: 6)), .straight]
        )
    }

    @Test func waypointsLegsAndModesAreRestoredAsStored() throws {
        let draft = try #require(ItineraryDraft(restoring: saved))

        #expect(draft.sport == .ride)
        #expect(draft.waypoints.map(\.coordinate) == [a, b, c])
        #expect(draft.legs.map(\.mode) == [.follow, .straight])
        #expect(draft.legs[0].path == [a, corner, b])
        #expect(draft.legs[1].path == nil)
    }

    @Test func nothingIsLeftToRoute() throws {
        let draft = try #require(ItineraryDraft(restoring: saved))

        #expect(draft.legs.allSatisfy { $0.state == .computed })
        #expect(draft.requestsForComputingLegs().isEmpty)
        #expect(draft.saveIssue == nil)
    }

    /// Saved again untouched, the Itinerary sends exactly what was stored.
    @Test func anUntouchedDraftSavesWhatWasLoaded() throws {
        let draft = try #require(ItineraryDraft(restoring: saved))

        let creation = try draft.creation(id: saved.id, name: saved.name)

        #expect(creation.waypoints == saved.waypoints)
        #expect(creation.legs == saved.legs)
        #expect(creation.sport == .ride)
    }

    @Test func legsThatDoNotJoinTheWaypointsAreRefused() {
        let broken = SavedItinerary(id: .fixture(7), name: "Cassé", sport: .run, waypoints: [a, b], legs: [.straight, .straight])

        #expect(ItineraryDraft(restoring: broken) == nil)
    }
}
