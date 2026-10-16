import Foundation
import Testing
@testable import StravaClone

/// The realtime messages of #92/#93 (`activity.updated`, `packages/realtime/src/events.ts`) read
/// as Activity events (ADR-033 §8).
struct RealtimeActivityEventSourceTests {
    private func event(_ message: String) throws -> ActivityEvent? {
        RealtimeActivityEventSource.event(from: try #require(RealtimeEvent.decode(Data(message.utf8))))
    }

    @Test func readsAnUpdate() throws {
        let event = try event(#"""
            {"v":1,"t":"activity.updated","id":"evt_1","data":{"activityId":"7c9e6679-7425-40de-944b-e07fc1f90ae7","changedFields":["stats"]}}
            """#)

        #expect(event == .updated(ActivityID(UUID(uuidString: "7c9e6679-7425-40de-944b-e07fc1f90ae7")!)))
    }

    @Test func ignoresOtherTypesAndUnreadablePayloads() throws {
        #expect(try event(#"{"v":1,"t":"activity.processed","id":"e","data":{"activityId":"7c9e6679-7425-40de-944b-e07fc1f90ae7"}}"#) == nil)
        #expect(try event(#"{"v":1,"t":"activity.updated","id":"e","data":{"activityId":"act_1","changedFields":["title"]}}"#) == nil)
    }
}
