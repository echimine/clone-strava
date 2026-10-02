import Foundation
import Testing
@testable import StravaClone

struct RealtimeEventTests {
    @Test func decodesAnEventEnvelope() throws {
        let message = Data(#"{"v":1,"t":"activity_import.completed","id":"evt_1","data":{"importId":"8C1B5D0A-1F2E-4C3D-9A8B-7C6D5E4F3A2B","status":"imported"}}"#.utf8)

        let event = try #require(RealtimeEvent.decode(message))

        #expect(event.type == "activity_import.completed")
        #expect(event.id == "evt_1")
        struct Payload: Decodable { let status: String }
        #expect(event.payload(as: Payload.self)?.status == "imported")
    }

    @Test func ignoresControlMessagesAndUnknownVersions() {
        #expect(RealtimeEvent.decode(Data(#"{"a":"sub:ok","topic":"user:1"}"#.utf8)) == nil)
        #expect(RealtimeEvent.decode(Data(#"{"v":2,"t":"x","id":"1","data":{}}"#.utf8)) == nil)
        #expect(RealtimeEvent.decode(Data("not json".utf8)) == nil)
    }

    @Test func buildsControlMessages() {
        #expect(RealtimeControlMessage.subscribe(topic: realtimeUserTopic("u1")) == #"{"a":"sub","topic":"user:u1"}"#)
        #expect(RealtimeControlMessage.ping == #"{"a":"ping"}"#)
    }

    @Test func dropsDuplicateIdsWithBoundedMemory() {
        var deduplicator = RealtimeEventDeduplicator(capacity: 2)
        let accepted = ["a", "a", "b", "c", "a"].map { deduplicator.accept($0) }
        // The second "a" is a duplicate; the last one is accepted again once evicted.
        #expect(accepted == [true, false, true, true, true])
    }
}
