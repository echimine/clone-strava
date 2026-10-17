import Foundation
@testable import StravaClone

extension ActivityChanges {
    /// What `stream` received, up to a marker this publishes now: a test that reads what was
    /// published ends even when nothing was.
    func published(on stream: AsyncStream<ActivityChange>) async -> [ActivityChange] {
        let marker = ActivityChange.deleted(ActivityID())
        publish(marker)
        var received: [ActivityChange] = []
        for await change in stream {
            if change == marker { break }
            received.append(change)
        }
        return received
    }
}
