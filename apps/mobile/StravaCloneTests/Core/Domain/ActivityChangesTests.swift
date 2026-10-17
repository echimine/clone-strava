import Foundation
import Testing
@testable import StravaClone

/// The Core change stream of ADR-033 §7: every subscriber gets each change, in order.
struct ActivityChangesTests {
    @Test func everySubscriberReceivesTheChangesInOrder() async {
        let changes = ActivityChanges()
        let first = changes.subscribe()
        let second = changes.subscribe()
        let id = ActivityID()
        let engagement = ActivityEngagement(kudosCount: 1, commentCount: 4, viewerHasKudoed: true)

        changes.publish(.engagement(id, engagement))
        changes.publish(.deleted(id))

        for stream in [first, second] {
            var received: [ActivityChange] = []
            for await change in stream {
                received.append(change)
                if received.count == 2 { break }
            }
            #expect(received == [.engagement(id, engagement), .deleted(id)])
        }
    }
}
