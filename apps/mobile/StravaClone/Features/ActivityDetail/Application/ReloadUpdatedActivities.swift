import Foundation

/// The feed's cards follow `activity.updated` on the owner's topic (ADR-033 §8): each event
/// reloads that Activity and publishes it on the Core change stream, which the feed applies
/// (§7); an Activity gone by then is published as deleted. Runs while signed in and in the
/// foreground, like the realtime connection.
struct ReloadUpdatedActivities: Sendable {
    let loadDetail: LoadActivityDetail
    let changes: ActivityChanges
    let events: any ActivityEventSource

    func run() async {
        for await event in await events.activityEvents() {
            guard case .updated(let id) = event else { continue }
            do {
                changes.publish(.updated(try await loadDetail(id).post))
            } catch .notFound {
                changes.publish(.deleted(id))
            } catch {
                // The card keeps its values until the next refresh.
            }
        }
    }
}
