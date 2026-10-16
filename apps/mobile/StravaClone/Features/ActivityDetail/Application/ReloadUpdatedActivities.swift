import Foundation

/// The feed's cards follow `activity.updated` and `activity.deleted` on the owner's topic
/// (ADR-033 §8): an update reloads that Activity and publishes it on the Core change stream,
/// which the feed applies (§7); a deletion, or an Activity gone by then, is published as
/// deleted. Runs while signed in and in the foreground, like the realtime connection.
struct ReloadUpdatedActivities: Sendable {
    let loadDetail: LoadActivityDetail
    let changes: ActivityChanges
    let events: any ActivityEventSource

    func run() async {
        for await event in await events.activityEvents() {
            switch event {
            case .updated(let id):
                do {
                    changes.publish(.updated(try await loadDetail(id).post))
                } catch .notFound {
                    changes.publish(.deleted(id))
                } catch {
                    // The card keeps its values until the next refresh.
                }
            case .deleted(let id):
                changes.publish(.deleted(id))
            }
        }
    }
}
