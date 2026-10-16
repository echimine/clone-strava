import Foundation

/// The detail kept live (ADR-034 §5): while `run()` runs (the page's `.task`, so while the
/// detail is shown), the Activity's comment and kudos events reach its stores. Ending `run()`
/// ends the subscription. `activity.updated` / `activity.deleted` are the detail store's own
/// (`observeEvents()`), which this subscription feeds for viewers other than the author.
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
                await comments.created(id)
            case .commentUpdated(let id):
                await comments.updated(id)
            case .commentDeleted(let id):
                comments.deleted(id)
            case .kudosChanged:
                // The reload brings the count, `viewerHasKudoed` and the kudos row.
                await detail.load()
            }
        }
    }
}
