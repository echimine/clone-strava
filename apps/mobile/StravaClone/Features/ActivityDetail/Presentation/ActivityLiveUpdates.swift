import Foundation

/// An open detail or Kudos and comments screen kept live (ADR-034 §5, ADR-036 §8): while `run()`
/// runs (the page's `.task`, so while the screen is shown), the Activity's comment and kudos
/// events reach its stores. Ending `run()` ends the subscription. `activity.updated` /
/// `activity.deleted` are the detail store's own (`observeEvents()`), which this subscription
/// feeds for viewers other than the author.
@MainActor
struct ActivityLiveUpdates {
    let events: any ActivityLiveEventSource
    let detail: ActivityDetailStore
    /// The thread, on the Kudos and comments screen. Without it (the detail), a comment posted
    /// or deleted elsewhere only changes the counts, read again.
    var comments: ActivityCommentsStore?
    /// The givers' list, on the Kudos and comments screen.
    var kudos: KudosListStore?

    /// The Kudos and comments screen: the Activity, its thread and its givers.
    init(events: any ActivityLiveEventSource, engagement: ActivityEngagementStore) {
        self.init(events: events, detail: engagement.detail, comments: engagement.comments, kudos: engagement.kudos)
    }

    init(
        events: any ActivityLiveEventSource,
        detail: ActivityDetailStore,
        comments: ActivityCommentsStore? = nil,
        kudos: KudosListStore? = nil
    ) {
        self.events = events
        self.detail = detail
        self.comments = comments
        self.kudos = kudos
    }

    func run() async {
        for await event in events.events(of: detail.id) {
            switch event {
            case .reconnected:
                // Catch-up: whatever happened while disconnected.
                async let reloadedDetail: Void = detail.load()
                async let reloadedComments: Void? = comments?.load()
                async let reloadedKudos: Void? = kudos?.load()
                _ = await (reloadedDetail, reloadedComments, reloadedKudos)
            case .commentCreated(let id):
                if let comments {
                    await comments.created(id)
                } else {
                    await detail.load()
                }
            case .commentUpdated(let id):
                await comments?.updated(id)
            case .commentDeleted(let id):
                if let comments {
                    comments.deleted(id)
                } else {
                    await detail.load()
                }
            case .kudosChanged:
                // The reload brings the count, `viewerHasKudoed` and the kudos row.
                async let reloadedDetail: Void = detail.load()
                async let reloadedKudos: Void? = kudos?.load()
                _ = await (reloadedDetail, reloadedKudos)
            }
        }
    }
}
