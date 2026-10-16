import Foundation
import UIKit

/// Keeps work going for a while once the app leaves the foreground (`beginBackgroundTask`).
@MainActor
protocol BackgroundTaskRunning {
    func run(_ name: String, _ work: @MainActor () async -> Void) async
}

/// `BackgroundTaskRunning` over `UIApplication`: what is unfinished when iOS ends the task
/// resumes on the next trigger (ADR-031 §14).
struct UIKitBackgroundTasks: BackgroundTaskRunning {
    func run(_ name: String, _ work: @MainActor () async -> Void) async {
        let application = UIApplication.shared
        let task = BackgroundTaskBox()
        task.id = application.beginBackgroundTask(withName: name) {
            task.end(in: application)
        }
        await work()
        task.end(in: application)
    }
}

@MainActor
private final class BackgroundTaskBox {
    var id = UIBackgroundTaskIdentifier.invalid

    func end(in application: UIApplication) {
        guard id != .invalid else { return }
        application.endBackgroundTask(id)
        id = .invalid
    }
}

/// The queue coordinator of ADR-031 §14: wakes `ActivitySender` and the Itinerary changes on
/// the shared triggers, so no feature imports another. It also follows the Activities in
/// `processing`: once processed, the feed reloads its first page, then the local Activity is
/// wiped.
///
/// Triggers: right after Save, return to the foreground, network back, feed pull-to-refresh
/// (all but Save skip the backoff delay); tracking after each of them, each realtime
/// (re)connection and `activity.processed` / `activity.failed`. The worker is fast enough for
/// that event to arrive before the `complete` answer, while nothing is in `processing` yet:
/// tracking once the queue is sent catches the Activity all the same.
@MainActor
final class SyncQueueCoordinator {
    nonisolated static let activityEvents: Set<String> = ["activity.processed", "activity.failed"]

    private let activitySender: ActivitySender
    private let localActivities: GRDBLocalActivityStore
    private let sendItineraryChanges: @MainActor () async -> Void
    private let stopItineraryChanges: @MainActor @Sendable () -> Void
    private let reloadFeed: @MainActor () async -> Bool
    private let backgroundTasks: any BackgroundTaskRunning

    init(
        activitySender: ActivitySender,
        localActivities: GRDBLocalActivityStore,
        sendItineraryChanges: @escaping @MainActor () async -> Void,
        stopItineraryChanges: @escaping @MainActor @Sendable () -> Void = {},
        reloadFeed: @escaping @MainActor () async -> Bool,
        backgroundTasks: any BackgroundTaskRunning = UIKitBackgroundTasks()
    ) {
        self.activitySender = activitySender
        self.localActivities = localActivities
        self.sendItineraryChanges = sendItineraryChanges
        self.stopItineraryChanges = stopItineraryChanges
        self.reloadFeed = reloadFeed
        self.backgroundTasks = backgroundTasks
    }

    /// Right after Save: the whole chain starts at once, under a background task, then the
    /// Activity is checked.
    func activitySaved() async {
        await backgroundTasks.run("activity-upload") {
            await activitySender.send()
        }
        await trackProcessing()
    }

    /// Return to the foreground (and sign-in): everything pending is sent, then the
    /// Activities in `processing` are checked.
    func appBecameActive() async {
        await drain()
    }

    func pullToRefresh() async {
        await drain()
    }

    /// `GET /v1/activities/:id` for each Activity in `processing`; the processed ones are wiped
    /// once the feed's first page has reloaded.
    func trackProcessing() async {
        let processed = await activitySender.trackProcessing()
        guard !processed.isEmpty, await reloadFeed() else { return }
        try? await localActivities.wipe(processed)
    }

    /// For the sign-out confirmation: the Activities that would be lost.
    func unsentActivityCount() async -> Int {
        (try? await localActivities.unsentCount()) ?? 0
    }

    /// Sign-out, once confirmed: the local Activities and their queued steps are wiped.
    func signOut() async {
        await activitySender.clear()
    }

    /// While signed in and in the foreground: sends when the network comes back, tracks on each
    /// realtime (re)connection and Activity event. Runs until cancelled.
    func observe(
        connectivity: AsyncStream<Bool>,
        connections: AsyncStream<Void>,
        events: AsyncStream<RealtimeEvent>
    ) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                var wasConnected: Bool?
                for await isConnected in connectivity {
                    defer { wasConnected = isConnected }
                    guard isConnected, wasConnected == false else { continue }
                    await self.drain()
                }
            }
            group.addTask {
                for await _ in connections {
                    await self.trackProcessing()
                }
            }
            group.addTask {
                for await event in events where Self.activityEvents.contains(event.type) {
                    await self.trackProcessing()
                }
            }
        }
    }

    /// The `BGAppRefreshTask` (ADR-031 §14): everything pending is sent, Activities then
    /// Itinerary changes, already within iOS's background time. Cancelling the caller (the
    /// task's expiration) stops the passes in flight; each operation stays at its step.
    func backgroundRefresh() async {
        let activitySender = activitySender
        let stopItineraryChanges = stopItineraryChanges
        await withTaskCancellationHandler {
            guard !Task.isCancelled else { return }
            await activitySender.send(ignoringBackoff: true)
            guard !Task.isCancelled else { return }
            await sendItineraryChanges()
        } onCancel: {
            Task { @MainActor in
                activitySender.cancelPass()
                stopItineraryChanges()
            }
        }
    }

    /// Everything pending is sent, then the Activities in `processing` are checked.
    private func drain() async {
        await backgroundTasks.run("sync-queue") {
            await activitySender.send(ignoringBackoff: true)
            await sendItineraryChanges()
        }
        await trackProcessing()
    }
}
