import Foundation
import Testing
@testable import StravaClone

/// The realtime messages of #28 (`packages/core/src/realtime/listeners/realtime-bridge.listener.ts`)
/// read as Itinerary events (ADR-030 §9).
struct RealtimeItineraryEventSourceTests {
    private func event(_ message: String) throws -> ItineraryEvent? {
        RealtimeItineraryEventSource.event(from: try #require(RealtimeEvent.decode(Data(message.utf8))))
    }

    @Test func readsASaveWithTheCommittedUpdatedAt() throws {
        let event = try event(#"""
            {"v":1,"t":"itinerary.saved","id":"evt_1","data":{"itineraryId":"00000000-0000-4000-8000-000000000001","updatedAt":"2026-10-10T08:00:00.500Z"}}
            """#)

        // Same instant as the API's answers, so an echo compares equal to the cached row.
        #expect(event == .saved(id: .fixture(1), updatedAt: .fixture()))
    }

    @Test func readsADelete() throws {
        let event = try event(#"""
            {"v":1,"t":"itinerary.deleted","id":"evt_2","data":{"itineraryId":"00000000-0000-4000-8000-000000000002"}}
            """#)

        #expect(event == .deleted(id: .fixture(2)))
    }

    @Test func ignoresOtherTypesAndUnreadablePayloads() throws {
        #expect(try event(#"{"v":1,"t":"activity.processed","id":"e","data":{"itineraryId":"00000000-0000-4000-8000-000000000001"}}"#) == nil)
        #expect(try event(#"{"v":1,"t":"itinerary.deleted","id":"e","data":{"itineraryId":"itn_1"}}"#) == nil)
        #expect(try event(#"{"v":1,"t":"itinerary.saved","id":"e","data":{"itineraryId":"00000000-0000-4000-8000-000000000001"}}"#) == nil)
        #expect(try event(#"{"v":1,"t":"itinerary.saved","id":"e","data":{"itineraryId":"00000000-0000-4000-8000-000000000001","updatedAt":"hier"}}"#) == nil)
    }
}
