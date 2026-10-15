import Foundation
import Testing
@testable import StravaClone

/// `BGTaskScheduler` as the background refresh asks for it: submissions and cancellations.
final class RecordingRefreshScheduler: BackgroundRefreshScheduling, @unchecked Sendable {
    private let submissions = Locked<[Date]>([])
    private let cancellations = Locked(0)
    private let request = Locked<Date?>(nil)

    var submitted: [Date] { submissions.value }
    var cancelled: Int { cancellations.value }
    /// The `earliestBeginDate` of the request iOS holds, if any.
    var pending: Date? { request.value }

    func submit(earliestBeginDate: Date) throws {
        submissions.value.append(earliestBeginDate)
        request.value = earliestBeginDate
    }

    func cancel() {
        cancellations.value += 1
        request.value = nil
    }
}

/// A `BGAppRefreshTask` launched by hand: its expiration is fired by the test.
@MainActor
final class FakeRefreshTask: BackgroundRefreshTask {
    var expirationHandler: (() -> Void)?
    private(set) var completions: [Bool] = []

    func setTaskCompleted(success: Bool) {
        completions.append(success)
    }
}

/// Nested in `ActivitySenderTests` to share its serialized network stub.
extension ActivitySenderTests {
    /// The `BGAppRefreshTask` of ADR-031 §14: scheduled only while `sync_operation` is not
    /// empty, it drains the Activities and the Itinerary changes through the queue coordinator.
    @MainActor
    struct SyncQueueBackgroundRefreshTests {
        nonisolated private static let now = ActivitySenderHarness.now
        private let harness: ActivitySenderHarness
        private let scheduler = RecordingRefreshScheduler()

        init() throws {
            ActivitySenderHarness.resetNetwork()
            harness = try ActivitySenderHarness()
        }

        private func makeRefresh() -> SyncQueueBackgroundRefresh {
            SyncQueueBackgroundRefresh(
                queue: SyncQueueState(database: harness.database),
                scheduler: scheduler,
                refresh: {},
                now: { Self.now }
            )
        }

        @Test func noTaskIsScheduledWhileTheQueueIsEmpty() async throws {
            let observing = Task { await makeRefresh().observeQueue() }
            defer { observing.cancel() }

            #expect(await eventually { scheduler.cancelled > 0 })
            #expect(scheduler.submitted.isEmpty)
        }

        @Test func aTaskIsScheduledFifteenMinutesOutAsSoonAsAnOperationIsAdded() async throws {
            let observing = Task { await makeRefresh().observeQueue() }
            defer { observing.cancel() }
            #expect(await eventually { scheduler.cancelled > 0 })

            try await harness.saveRecordedActivity()

            #expect(await eventually { !scheduler.submitted.isEmpty })
            #expect(scheduler.submitted == [Self.now.addingTimeInterval(15 * 60)])
        }

        @Test func theRequestIsCancelledOnceTheQueueIsEmpty() async throws {
            try await harness.saveRecordedActivity()
            let observing = Task { await makeRefresh().observeQueue() }
            defer { observing.cancel() }
            #expect(await eventually { scheduler.pending != nil })

            try await harness.store.wipe([harness.id])

            #expect(await eventually { scheduler.pending == nil })
            #expect(scheduler.submitted.count == 1)
        }

        // MARK: - The task

        /// The real coordinator over the stubbed Activity network and a fake Itinerary server,
        /// both queues in the same database.
        private struct Drain {
            let refresh: SyncQueueBackgroundRefresh
            let itineraries: FakeItineraryRepository
            let changes: ItineraryChangeSender
            let cache: GRDBItineraryCache
        }

        private func makeDrain() -> Drain {
            let itineraries = FakeItineraryRepository()
            let cache = GRDBItineraryCache(database: harness.database)
            let changes = ItineraryChangeSender(
                repository: itineraries,
                cache: cache,
                queue: GRDBItineraryChangeQueue(database: harness.database),
                sessionRefresher: FakeSessionRefresher(),
                // The retry after the backoff never fires on its own: only the test's triggers send.
                sleep: ManualSleeper().sleep
            )
            let coordinator = SyncQueueCoordinator(
                activitySender: harness.makeSender(),
                localActivities: harness.store,
                sendItineraryChanges: { await changes.send(ignoringBackoff: true) },
                stopItineraryChanges: { changes.cancelPass() },
                reloadFeed: { true },
                backgroundTasks: RecordingBackgroundTasks()
            )
            let refresh = SyncQueueBackgroundRefresh(
                queue: SyncQueueState(database: harness.database),
                scheduler: scheduler,
                refresh: { await coordinator.backgroundRefresh() },
                now: { Self.now }
            )
            return Drain(refresh: refresh, itineraries: itineraries, changes: changes, cache: cache)
        }

        /// A rename made offline: queued, postponed.
        private func renameOffline(_ drain: Drain) async throws {
            try await drain.cache.save(.fixture(1, name: "Nom serveur"), mapPolyline: EncodedPolyline(value: "local"))
            try await drain.changes.rename(id: .fixture(1), to: "Boucle du parc")
        }

        private func routeTheWholeChain(uploading upload: ActivityURLProtocolStub.Answer = .status(200)) {
            let harness = harness
            ActivitySenderHarness.route { step in
                switch step {
                case "create": harness.created()
                case "upload": upload
                default: harness.completed()
                }
            }
        }

        @Test func theTaskSendsAPendingActivityAndAnItineraryRename() async throws {
            let drain = makeDrain()
            try await harness.saveRecordedActivity()
            try await renameOffline(drain)
            routeTheWholeChain()
            drain.itineraries.setChangeResult(.success(()))
            drain.itineraries.setDetail(.success(.fixture(1, name: "Nom serveur")), for: .fixture(1))
            let task = FakeRefreshTask()

            await drain.refresh.perform(task)

            #expect(try await harness.store.activity(harness.id)?.state == .processing)
            #expect(drain.itineraries.renameCalls.map(\.1).last == "Boucle du parc")
            #expect(await SyncQueueState(database: harness.database).pendingCount() == 0)
            #expect(task.completions == [true])
            #expect(scheduler.pending == nil)
        }

        @Test func theTaskIsScheduledAgainWhileOperationsRemain() async throws {
            let drain = makeDrain()
            try await harness.saveRecordedActivity()
            ActivitySenderHarness.route { _ in .offline }
            let task = FakeRefreshTask()

            await drain.refresh.perform(task)

            #expect(try await harness.store.activity(harness.id)?.state == .recorded)
            #expect(task.completions == [true])
            #expect(scheduler.pending == Self.now.addingTimeInterval(15 * 60))
        }

        @Test func anExpirationDuringTheUploadLeavesTheQueueCoherent() async throws {
            let drain = makeDrain()
            try await harness.saveRecordedActivity()
            try await renameOffline(drain)
            drain.itineraries.setChangeResult(.success(()))
            drain.itineraries.setDetail(.success(.fixture(1, name: "Nom serveur")), for: .fixture(1))
            routeTheWholeChain(uploading: .hang)
            let task = FakeRefreshTask()
            let renamesBefore = drain.itineraries.renameCalls.count

            let performing = Task { await drain.refresh.perform(task) }
            #expect(await eventually { harness.requestLines.contains("PUT bucket") })
            task.expirationHandler?()
            await performing.value

            #expect(task.completions == [false])
            #expect(try await harness.store.activity(harness.id)?.state == .created)
            #expect(try await harness.store.operation(for: harness.id)?.step == .upload)
            #expect(drain.itineraries.renameCalls.count == renamesBefore)
            #expect(await SyncQueueState(database: harness.database).pendingCount() == 2)
            #expect(scheduler.pending != nil)

            // The next trigger resumes at the upload.
            routeTheWholeChain()
            await drain.refresh.perform(FakeRefreshTask())

            #expect(try await harness.store.activity(harness.id)?.state == .processing)
            #expect(await SyncQueueState(database: harness.database).pendingCount() == 0)
        }

        @Test func anExpirationDuringAServerDeleteKeepsItQueued() async throws {
            let drain = makeDrain()
            try await harness.saveRecordedActivity()
            let harness = harness
            ActivitySenderHarness.route { step in step == "create" ? harness.created() : .offline }
            await harness.makeSender().send()
            #expect(try await harness.store.delete(harness.id))
            ActivitySenderHarness.route { _ in .hang }
            let task = FakeRefreshTask()

            let performing = Task { await drain.refresh.perform(task) }
            #expect(await eventually { harness.requestLines.contains("DELETE /v1/activities/\(harness.id)") })
            task.expirationHandler?()
            await performing.value

            #expect(task.completions == [false])
            #expect(try await harness.store.operation(for: harness.id)?.step == .delete)
            #expect(await SyncQueueState(database: harness.database).pendingCount() == 1)
            #expect(scheduler.pending != nil)

            // The next trigger sends the delete.
            ActivitySenderHarness.route { _ in .status(204) }
            await drain.refresh.perform(FakeRefreshTask())

            #expect(try await harness.store.operation(for: harness.id) == nil)
            #expect(await SyncQueueState(database: harness.database).pendingCount() == 0)
        }
    }
}
