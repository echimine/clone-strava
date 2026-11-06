import Foundation
import Testing
@testable import StravaClone

/// The path the editor hands over when it draws a Segment (ADR-039 §15): one line, once settled.
@MainActor
struct ItineraryEditorDrawnPathTests {
    private let a = Coordinate(latitude: 45.900, longitude: 6.120)
    private let b = Coordinate(latitude: 45.902, longitude: 6.122)
    private let c = Coordinate(latitude: 45.904, longitude: 6.121)

    @Test func noPathBeforeAStartAndAFinish() async {
        let editor = ItineraryEditor(sport: .run, router: FakeItineraryRouter())
        #expect(editor.settledPath == nil)
        #expect(!editor.hasStartAndFinish)
        editor.addWaypoint(at: a)
        await editor.settle()
        #expect(editor.settledPath == nil)
    }

    @Test func noPathWhileALegIsRouted() async {
        let router = FakeItineraryRouter()
        await router.hold()
        let editor = ItineraryEditor(sport: .run, router: router)
        editor.addWaypoint(at: a)
        editor.addWaypoint(at: b)
        await router.waitForCalls(1)

        #expect(editor.hasStartAndFinish)
        #expect(editor.settledPath == nil)
        await router.release()
        await editor.settle()
        #expect(editor.settledPath != nil)
    }

    @Test func joinsTheRoutedLegsWithoutRepeatingTheirCommonWaypoint() async throws {
        let editor = ItineraryEditor(sport: .run, router: FakeItineraryRouter())
        for point in [a, b, c] {
            editor.addWaypoint(at: point)
        }
        await editor.settle()

        let path = try #require(editor.settledPath)
        let legs = editor.draft.legs.indices.map { editor.draft.geometry(ofLegAt: $0) }
        #expect(path == legs[0] + legs[1].dropFirst())
        #expect(path.first == legs[0].first)
        #expect(path.last == legs[1].last)
        #expect(zip(path, path.dropFirst()).allSatisfy { $0 != $1 })
    }
}
