import BackgroundTasks
import Foundation

/// Submits and cancels the one `BGAppRefreshTaskRequest` of the sync queue.
protocol BackgroundRefreshScheduling: Sendable {
    func submit(earliestBeginDate: Date) throws
    func cancel()
}

/// What the background refresh needs of a `BGAppRefreshTask`.
@MainActor
protocol BackgroundRefreshTask: AnyObject {
    var expirationHandler: (() -> Void)? { get set }
    func setTaskCompleted(success: Bool)
}

/// The `BGAppRefreshTask` of ADR-031 §14 (amends ADR-008 §3): empties `sync_operation` while
/// the app is not open. A request is pending only while the queue holds operations: submitted
/// as soon as one is added (`earliestBeginDate` 15 min out), cancelled once the queue is empty.
@MainActor
final class SyncQueueBackgroundRefresh {
    nonisolated static let identifier = "fr.echimine.stravaclone.sync-queue"
    nonisolated static let delay: TimeInterval = 15 * 60

    private let queue: SyncQueueState
    private let scheduler: any BackgroundRefreshScheduling
    private let refresh: @MainActor () async -> Void
    private let now: @Sendable () -> Date
    private var isScheduled = false

    init(
        queue: SyncQueueState,
        scheduler: any BackgroundRefreshScheduling,
        refresh: @escaping @MainActor () async -> Void,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.queue = queue
        self.scheduler = scheduler
        self.refresh = refresh
        self.now = now
    }

    /// Follows the size of the queue for as long as the app runs (until cancelled).
    func observeQueue() async {
        for await count in queue.pendingCounts() {
            if count > 0 {
                schedule()
            } else {
                unschedule()
            }
        }
    }

    /// The task launched by iOS: drains both queues through the coordinator. The next request
    /// is submitted first, so a task cut short still has a successor; it is cancelled at the end
    /// if nothing remains. When iOS takes the time back, the sends are cancelled (each pending
    /// operation stays at its step) and the task ends unsuccessfully.
    func perform(_ task: any BackgroundRefreshTask) async {
        isScheduled = false
        if await queue.pendingCount() > 0 {
            schedule()
        }
        let refresh = refresh
        let work = Task { @MainActor in await refresh() }
        task.expirationHandler = { work.cancel() }
        await work.value
        if await queue.pendingCount() == 0 {
            unschedule()
        }
        task.setTaskCompleted(success: !work.isCancelled)
    }

    /// One submission per non-empty spell: another operation does not push the date back.
    private func schedule() {
        guard !isScheduled else { return }
        do {
            try scheduler.submit(earliestBeginDate: now().addingTimeInterval(Self.delay))
            isScheduled = true
        } catch {
            // The simulator has no `BGTaskScheduler`; the foreground triggers still drain.
        }
    }

    private func unschedule() {
        scheduler.cancel()
        isScheduled = false
    }
}

extension SyncQueueBackgroundRefresh {
    /// Registers the launch handler; must run before `didFinishLaunching` returns.
    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.identifier, using: .main) { [weak self] task in
            MainActor.assumeIsolated {
                guard let self, let task = task as? BGAppRefreshTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                Task { await self.perform(task) }
            }
        }
    }
}

extension BGAppRefreshTask: BackgroundRefreshTask {}

/// `BackgroundRefreshScheduling` over `BGTaskScheduler` (unavailable on the simulator: `submit`
/// throws there).
struct BGTaskSchedulerRefresh: BackgroundRefreshScheduling {
    func submit(earliestBeginDate: Date) throws {
        let request = BGAppRefreshTaskRequest(identifier: SyncQueueBackgroundRefresh.identifier)
        request.earliestBeginDate = earliestBeginDate
        try BGTaskScheduler.shared.submit(request)
    }

    func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: SyncQueueBackgroundRefresh.identifier)
    }
}
