import Foundation
import Testing
@testable import StravaClone

struct ImportTrackerTests {
    @Test func aRealtimeEventTriggersAnImmediateReload() async {
        let id = UUID()
        let repository = FakeActivityImportRepository()
        let events = FakeImportEventSource()
        // First poll: still processing; the reload after the event sees the result.
        repository.fetchResults = [.fixture(id: id, status: .processing), .fixture(id: id, status: .imported)]
        // A poll interval far longer than the test: only the event can finish it in time.
        let tracker = ImportTracker(repository: repository, events: events, pollInterval: .seconds(60), timeout: .seconds(5))

        Task {
            try? await Task.sleep(for: .milliseconds(50))
            events.continuation.yield(.completed(importId: UUID()))  // someone else's import: ignored
            events.continuation.yield(.completed(importId: id))
        }
        let result = await tracker.waitForFinalStatus(id: id)

        #expect(result?.status == .imported)
    }

    @Test func pollingFindsTheResultWithoutAnyEvent() async {
        let id = UUID()
        let repository = FakeActivityImportRepository()
        repository.fetchResults = [
            .fixture(id: id, status: .processing),
            .fixture(id: id, status: .processing),
            .fixture(id: id, status: .duplicate, activityId: "other"),
        ]
        let tracker = ImportTracker(
            repository: repository,
            events: FakeImportEventSource(),
            pollInterval: .milliseconds(10),
            timeout: .seconds(5)
        )

        let result = await tracker.waitForFinalStatus(id: id)

        #expect(result?.status == .duplicate)
        #expect(repository.fetchCount >= 3)
    }

    @Test func givesUpAfterTheTimeout() async {
        let tracker = ImportTracker(
            repository: FakeActivityImportRepository(),
            events: FakeImportEventSource(),
            pollInterval: .milliseconds(10),
            timeout: .milliseconds(100)
        )

        #expect(await tracker.waitForFinalStatus(id: UUID()) == nil)
    }
}
