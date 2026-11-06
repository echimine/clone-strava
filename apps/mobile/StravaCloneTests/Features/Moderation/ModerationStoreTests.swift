import Foundation
import Testing
@testable import StravaClone

@MainActor
struct ModerationStoreTests {
    private let lea = ActivityAuthor(id: "lea", displayName: "Léa Martin", avatarURL: nil)

    private func makeStore(
        _ repository: FakeModerationRepository,
        changes: ActivityChanges = ActivityChanges(),
        analytics: FakeAnalyticsClient = FakeAnalyticsClient()
    ) -> ModerationStore {
        ModerationStore(
            reportContent: ReportContent(repository: repository),
            blockAthlete: BlockAthlete(repository: repository),
            changes: changes,
            analytics: analytics
        )
    }

    @Test func offersImpersonationForAnAthleteOnly() {
        let store = makeStore(FakeModerationRepository())
        store.report(.comment("c1", by: lea))
        #expect(store.reasons == [.spam, .harassment, .sexualOrViolent, .other])
        store.report(.athlete(lea))
        #expect(store.reasons == [.spam, .harassment, .sexualOrViolent, .impersonation, .other])
    }

    /// ADR-039 §11: a Segment has no athlete shown, and reporting it never hides it.
    @Test func reportingASegmentNeverHidesItNorOffersToBlock() async {
        let repository = FakeModerationRepository()
        let store = makeStore(repository)
        var hidden: [ReportHiding] = []
        store.report(.segment("s1")) { hidden.append($0) }
        #expect(store.reasons == [.spam, .harassment, .sexualOrViolent, .other])
        #expect(ModerationMessages.reportTitle(.segment) == "Signaler ce Segment")
        store.reason = .spam

        await store.send()

        #expect(repository.calls == [.report(.segment("s1"), .spam, note: nil)])
        #expect(store.sheetPhase == .done(.reported))
        #expect(hidden.isEmpty)
        #expect(store.sheet?.target.author == nil)
    }

    @Test func needsAReasonAndANoteWithAutre() {
        let store = makeStore(FakeModerationRepository())
        store.report(.comment("c1", by: lea))
        #expect(!store.canSend)
        store.reason = .spam
        #expect(store.canSend)
        store.reason = .other
        store.note = "   "
        #expect(!store.canSend)
        store.note = "Propos déplacés"
        #expect(store.canSend)
    }

    @Test func keepsTheNoteTo500Characters() {
        let store = makeStore(FakeModerationRepository())
        store.report(.comment("c1", by: lea))
        store.note = String(repeating: "a", count: 600)
        #expect(store.note.count == 500)
    }

    @Test func reportingACommentHidesItAndThanks() async {
        let repository = FakeModerationRepository()
        let store = makeStore(repository)
        var hidden: [ReportHiding] = []
        store.report(.comment("c1", by: lea)) { hidden.append($0) }
        store.reason = .harassment
        store.note = "  Insultes "

        await store.send()

        #expect(repository.calls == [.report(.comment("c1", by: lea), .harassment, note: "Insultes")])
        #expect(store.sheetPhase == .done(.reported))
        #expect(hidden == [.target])
    }

    @Test func aReportedActivityLeavesEveryListEvenWhenAlreadyReported() async {
        let repository = FakeModerationRepository()
        repository.reportResult = .success(.alreadyReported)
        let changes = ActivityChanges()
        let stream = changes.subscribe()
        let store = makeStore(repository, changes: changes)
        let id = ActivityID()
        store.report(.activity(id, by: lea))
        store.reason = .spam

        await store.send()

        #expect(store.sheetPhase == .done(.alreadyReported))
        #expect(await changes.published(on: stream) == [.deleted(id)])
    }

    @Test func aReportedAthleteIsNotHidden() async {
        let changes = ActivityChanges()
        let stream = changes.subscribe()
        let store = makeStore(FakeModerationRepository(), changes: changes)
        var hidden: [ReportHiding] = []
        store.report(.athlete(lea)) { hidden.append($0) }
        store.reason = .impersonation

        await store.send()

        #expect(hidden.isEmpty)
        #expect(await changes.published(on: stream).isEmpty)
    }

    @Test func aFailedReportHidesNothingAndShowsAToast() async {
        let repository = FakeModerationRepository()
        repository.reportResult = .failure(.offline)
        let store = makeStore(repository)
        var hidden: [ReportHiding] = []
        store.report(.comment("c1", by: lea)) { hidden.append($0) }
        store.reason = .spam

        await store.send()

        #expect(store.sheetPhase == .editing)
        #expect(store.sheetToast == ModerationMessages.message(for: .offline))
        #expect(hidden.isEmpty)
        #expect(store.sheet != nil)
    }

    @Test func blockingTheReportedAuthorHidesThemEverywhereAndClosesTheSheet() async {
        let repository = FakeModerationRepository()
        let changes = ActivityChanges()
        let stream = changes.subscribe()
        let analytics = FakeAnalyticsClient()
        let store = makeStore(repository, changes: changes, analytics: analytics)
        var hidden: [ReportHiding] = []
        store.report(.athlete(lea)) { hidden.append($0) }
        store.reason = .spam
        await store.send()

        store.blockReportedAuthor()
        #expect(store.blockRequest == .init(athlete: lea, source: .reportConfirmation))
        await store.confirmBlock()

        #expect(repository.calls.last == .block("lea"))
        #expect(store.sheet == nil)
        #expect(hidden == [.author])
        #expect(analytics.events == [.athleteBlocked(source: .reportConfirmation)])
        #expect(await changes.published(on: stream) == [.authorHidden(athleteId: "lea")])
    }

    @Test func blockingFromAProfileAsksFirstThenRunsOnBlocked() async {
        let repository = FakeModerationRepository()
        let analytics = FakeAnalyticsClient()
        let store = makeStore(repository, analytics: analytics)
        var blocked = false
        store.requestBlock(lea) { blocked = true }
        #expect(repository.calls.isEmpty)

        await store.confirmBlock()

        #expect(blocked)
        #expect(store.toast == ModerationMessages.blocked("Léa"))
        #expect(analytics.events == [.athleteBlocked(source: .profile)])
    }

    @Test func aCancelledOrFailedBlockChangesNothing() async {
        let repository = FakeModerationRepository()
        let store = makeStore(repository)
        var blocked = false
        store.requestBlock(lea) { blocked = true }
        store.cancelBlock()
        await store.confirmBlock()
        #expect(repository.calls.isEmpty)

        repository.blockResult = .failure(.network)
        store.requestBlock(lea) { blocked = true }
        await store.confirmBlock()
        #expect(!blocked)
        #expect(store.toast == ModerationMessages.message(for: .network))
    }
}

@MainActor
struct BlockedAthletesStoreTests {
    private let lea = BlockedAthlete(athlete: ActivityAuthor(id: "lea", displayName: "Léa Martin", avatarURL: nil), blockedAt: .now)
    private let tom = BlockedAthlete(athlete: ActivityAuthor(id: "tom", displayName: "Tom", avatarURL: nil), blockedAt: .now)

    private func makeStore(_ repository: FakeModerationRepository, analytics: FakeAnalyticsClient = FakeAnalyticsClient()) -> BlockedAthletesStore {
        BlockedAthletesStore(
            loadBlockedAthletes: LoadBlockedAthletes(repository: repository),
            unblockAthlete: UnblockAthlete(repository: repository),
            analytics: analytics
        )
    }

    @Test func listsThoseTheViewerBlocked() async {
        let repository = FakeModerationRepository()
        repository.listResult = .success([lea, tom])
        let store = makeStore(repository)

        await store.load()

        #expect(store.phase == .loaded)
        #expect(store.athletes == [lea, tom])
    }

    @Test func unblockingAfterTheConfirmationRemovesTheAthlete() async {
        let repository = FakeModerationRepository()
        repository.listResult = .success([lea, tom])
        let analytics = FakeAnalyticsClient()
        let store = makeStore(repository, analytics: analytics)
        await store.load()

        store.unblockCandidate = lea
        await store.confirmUnblock()

        #expect(repository.calls.last == .unblock("lea"))
        #expect(store.athletes == [tom])
        #expect(analytics.events == [.athleteUnblocked])
        #expect(analytics.events.first?.properties == ["source": .string("settings")])
    }

    @Test func aFailedUnblockKeepsTheAthleteWithAToast() async {
        let repository = FakeModerationRepository()
        repository.listResult = .success([lea])
        repository.unblockResult = .failure(.offline)
        let store = makeStore(repository)
        await store.load()

        store.unblockCandidate = lea
        await store.confirmUnblock()

        #expect(store.athletes == [lea])
        #expect(store.toast == ModerationMessages.message(for: .offline))
    }

    @Test func aFailedFirstLoadShowsRetry() async {
        let repository = FakeModerationRepository()
        repository.listResult = .failure(.network)
        let store = makeStore(repository)

        await store.load()

        #expect(store.phase == .failed(ModerationMessages.message(for: .network)))
    }
}
