import Foundation

/// The feed's cards follow `activity.updated` and `activity.deleted` on the owner's topic
/// (ADR-033 §8): an update reloads that Activity and publishes it on the Core change stream,
/// which the feed applies (§7); a deletion, or an Activity gone by then, is published as
/// deleted. Runs while signed in and in the foreground, like the realtime connection.
///
/// Only the viewer's own Activities: an open detail of another athlete's Activity also brings
/// its events onto the connection (`activity:{id}`, ADR-034 §5), which carries no topic, and
/// the feed does not follow others' Activities live (ADR-033 §10).
struct ReloadUpdatedActivities: Sendable {
    let loadDetail: LoadActivityDetail
    let changes: ActivityChanges
    /// `activity.updated` / `activity.deleted` from the shared connection, any topic.
    let events: any ActivityEventSource
    /// Whether an Activity is the viewer's own, e.g. one of their cards in the feed.
    let isViewersOwn: @MainActor @Sendable (ActivityID) -> Bool

    func run() async {
        for await event in await events.activityEvents() {
            switch event {
            case .updated(let id):
                guard await isViewersOwn(id) else { continue }
                do {
                    changes.publish(.updated(try await loadDetail(id).post))
                } catch .notFound {
                    changes.publish(.deleted(id))
                } catch {
                    // The card keeps its values until the next refresh.
                }
            case .deleted(let id):
                guard await isViewersOwn(id) else { continue }
                changes.publish(.deleted(id))
            }
        }
    }
}
