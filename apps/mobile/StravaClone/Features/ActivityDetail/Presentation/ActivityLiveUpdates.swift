import Foundation

/// The detail kept live (ADR-034 §5): while `run()` runs (the page's `.task`, so while the
/// detail is shown), the Activity's realtime events reach its stores. Ending `run()` ends the
/// subscription.
@MainActor
struct ActivityLiveUpdates {
    let events: any ActivityLiveEventSource
    let detail: ActivityDetailStore
    let comments: ActivityCommentsStore

    func run() async {
        for await event in events.events(of: detail.id) {
            switch event {
            case .reconnected:
                // Catch-up: whatever happened while disconnected.
                async let reloadedDetail: Void = detail.load()
                async let reloadedComments: Void = comments.load()
                _ = await (reloadedDetail, reloadedComments)
            case .commentCreated(let id):
                // Known already, in any state: the echo of my own send.
                guard !comments.knows(id) else { continue }
                await comments.refresh(id)
            case .commentUpdated(let id):
                // Only the fetched comment tells whether it changed: the echo of my own edit
                // leaves the thread as it is.
                await comments.refresh(id)
            case .commentDeleted(let id):
                comments.remove(id)
            case .kudosChanged, .activityUpdated:
                // The reload brings the engagement and the kudos row; a `404` (made private)
                // shows the unavailable state.
                await detail.load()
            case .activityDeleted:
                detail.activityWasDeleted()
                return // ends the subscription
            }
        }
    }
}
