import Foundation
import Testing
@testable import StravaClone

/// What "Enregistrer" sends from the editor (ADR-030 §6): built from a draft traced on the
/// fake road network of `FakeItineraryRouter`.
@MainActor
struct ItineraryDraftSavingTests {
    private let a = Coordinate(latitude: 45.900, longitude: 6.120)
    private let b = Coordinate(latitude: 45.901, longitude: 6.121)
    private let c = Coordinate(latitude: 45.910, longitude: 6.121)

    private func trace(_ points: [Coordinate], router: FakeItineraryRouter = FakeItineraryRouter()) async -> ItineraryEditor {
        let editor = ItineraryEditor(sport: .hike, router: router)
        for point in points {
            editor.addWaypoint(at: point)
        }
        await editor.settle()
        return editor
    }

    @Test func aFollowLegIsSentWithItsPathAsPolyline6() async throws {
        let editor = await trace([a, b])

        let creation = try editor.draft.creation(id: .fixture(1), name: "  Tour du lac  ")

        #expect(creation.id == .fixture(1))
        #expect(creation.name == "Tour du lac")
        #expect(creation.sport == .hike)
        #expect(creation.waypoints == [a, b])
        // The fake network turns at the corner (start.lat, end.lon).
        let corner = Coordinate(latitude: 45.900, longitude: 6.121)
        #expect(creation.legs == [.follow(EncodedPolyline(encoding: [a, corner, b], precision: 6))])
    }

    @Test func aLegWithNoPathIsSentStraight() async throws {
        let router = FakeItineraryRouter()
        await router.fail(with: .noPath)
        let editor = await trace([a, b, c], router: router)

        let creation = try editor.draft.creation(id: .fixture(1), name: "Ligne droite")

        #expect(creation.legs == [.straight, .straight])
    }

    @Test func aStartAndAFinishAreNeeded() async {
        let editor = await trace([a])

        #expect(throws: ItinerarySaveIssue.incomplete) {
            try editor.draft.creation(id: .fixture(1), name: "Seul")
        }
    }

    @Test func savingWaitsForPendingLegs() async {
        let router = FakeItineraryRouter()
        await router.fail(with: .temporary)
        let editor = await trace([a, b], router: router)

        #expect(throws: ItinerarySaveIssue.legsPending) {
            try editor.draft.creation(id: .fixture(1), name: "En attente")
        }
    }

    @Test func theNameHasOneToAHundredCharactersOnceTrimmed() async throws {
        let editor = await trace([a, b])

        #expect(throws: ItinerarySaveIssue.invalidName) { try editor.draft.creation(id: .fixture(1), name: "   ") }
        #expect(throws: ItinerarySaveIssue.invalidName) {
            try editor.draft.creation(id: .fixture(1), name: String(repeating: "é", count: 101))
        }
        #expect(try editor.draft.creation(id: .fixture(1), name: String(repeating: "é", count: 100)).name.count == 100)
    }
}
