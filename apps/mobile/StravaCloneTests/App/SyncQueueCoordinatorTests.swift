import Foundation
import Testing
@testable import StravaClone

/// Background tasks as the coordinator asks for them, run inline.
@MainActor
final class RecordingBackgroundTasks: BackgroundTaskRunning {
    private(set) var names: [String] = []

    func run(_ name: String, _ work: @MainActor () async -> Void) async {
        names.append(name)
        await work()
    }
}

/// Nested in `ActivitySenderTests` to share its serialized network stub.
extension ActivitySenderTests {
    /// The queue coordinator in `App/` (ADR-031 §14): wakes `ActivitySender` on the shared
    /// triggers and wipes a processed Activity once the feed has reloaded.
    @MainActor
    struct SyncQueueCoordinatorTests {
        private let harness: ActivitySenderHarness
        private let backgroundTasks = RecordingBackgroundTasks()
        private let itineraryWakeUps = Locked(0)
        private let feedReloads = Locked(0)

        init() throws {
            ActivitySenderHarness.resetNetwork()
            harness = try ActivitySenderHarness()
        }

        private func makeCoordinator(feedReloads succeed: Bool = true) -> SyncQueueCoordinator {
            let itineraryWakeUps = itineraryWakeUps
            let feedReloads = feedReloads
            return SyncQueueCoordinator(
                activitySender: harness.makeSender(),
                sendItineraryChanges: { itineraryWakeUps.value += 1 },
                reloadFeed: {
                    feedReloads.value += 1
                    return succeed
                },
                backgroundTasks: backgroundTasks
            )
        }

        private func finished<T: Sendable>(_ values: [T]) -> AsyncStream<T> {
            AsyncStream { continuation in
                values.forEach { continuation.yield($0) }
                continuation.finish()
            }
        }

        private func routeTheWholeChain(online: Locked<Bool> = Locked(true)) {
            let harness = harness
            ActivitySenderHarness.route { step in
                guard online.value else { return .offline }
                switch step {
                case "create": return harness.created()
                case "upload": return .status(200)
                case "detail": return harness.detail("processed")
                default: return harness.completed()
                }
            }
        }

        @Test func afterSaveTheChainStartsUnderABackgroundTask() async throws {
            try await harness.saveRecordedActivity()
            routeTheWholeChain()

            await makeCoordinator().activitySaved()

            #expect(backgroundTasks.names == ["activity-upload"])
            #expect(try await harness.store.activity(harness.id)?.state == .processing)
        }

        @Test func savedOfflineTheActivityLeavesWhenTheNetworkComesBack() async throws {
            try await harness.saveRecordedActivity()
            let online = Locked(false)
            routeTheWholeChain(online: online)
            let coordinator = makeCoordinator()
            await coordinator.activitySaved()
            #expect(try await harness.store.activity(harness.id)?.state == .recorded)

            online.value = true
            await coordinator.observe(connectivity: finished([false, true]), connections: finished([]), events: finished([]))

            #expect(try await harness.store.activity(harness.id)?.state == .processing)
            #expect(itineraryWakeUps.value == 1)
        }

        @Test func theCurrentNetworkStateIsNotAComeback() async throws {
            await makeCoordinator().observe(connectivity: finished([true]), connections: finished([]), events: finished([]))

            #expect(itineraryWakeUps.value == 0)
        }

        @Test func backInTheForegroundEverythingPendingIsSentThenTracked() async throws {
            try await harness.saveRecordedActivity()
            routeTheWholeChain()

            await makeCoordinator().appBecameActive()

            #expect(harness.requestLines.last == "GET /v1/activities/\(harness.id)")
            #expect(feedReloads.value == 1)
            #expect(try await harness.store.activity(harness.id) == nil)
            #expect(itineraryWakeUps.value == 1)
        }

        @Test func anActivityEventReloadsTheFeedThenWipesTheProcessedActivity() async throws {
            try await harness.saveRecordedActivity()
            routeTheWholeChain()
            let coordinator = makeCoordinator()
            await coordinator.activitySaved()
            let event = try #require(RealtimeEvent.decode(Data(#"{"v":1,"t":"activity.processed","id":"evt_1","data":{"activityId":"\#(harness.id)","status":"processed","at":"2026-10-15T08:00:00Z"}}"#.utf8)))

            await coordinator.observe(connectivity: finished([]), connections: finished([]), events: finished([event]))

            #expect(feedReloads.value == 1)
            #expect(try await harness.store.activity(harness.id) == nil)
        }

        @Test func aRealtimeReconnectionTracksTheActivitiesInProcessing() async throws {
            try await harness.saveRecordedActivity()
            routeTheWholeChain()
            let coordinator = makeCoordinator()
            await coordinator.activitySaved()

            await coordinator.observe(connectivity: finished([]), connections: finished([()]), events: finished([]))

            #expect(try await harness.store.activity(harness.id) == nil)
        }

        @Test func theLocalActivityStaysUntilTheFeedHasReloaded() async throws {
            try await harness.saveRecordedActivity()
            routeTheWholeChain()
            let coordinator = makeCoordinator(feedReloads: false)
            await coordinator.activitySaved()

            await coordinator.trackProcessing()

            #expect(feedReloads.value == 1)
            #expect(try await harness.store.activity(harness.id)?.state == .processing)
        }
    }
}
