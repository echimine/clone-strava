import Foundation
import Testing
@testable import StravaClone

/// "Mettre en premier", "Supprimer" and "Modifier l'ordre" in "Photos et vidéos" (ADR-037 §8,
/// §10): the map stays 1st or 2nd, and the session tells what it changed.
@MainActor
struct MediaDraftOrderTests {
    private let a = ActivityMedia.fixture(), b = ActivityMedia.fixture(), c = ActivityMedia.fixture()

    private func draft(hasMap: Bool = true, mediaFirst: Bool = false) -> MediaDraft {
        MediaDraft(media: [a, b, c], hasMap: hasMap, mediaFirst: mediaFirst)
    }

    @Test func puttingAMediaFirstPlacesItBeforeTheMapAndTheMapRightAfter() {
        var draft = draft()

        draft.putFirst(c.id)

        #expect(draft.slides.map(\.id) == [.media(c.id), .map, .media(a.id), .media(b.id)])
        #expect(draft.mediaFirst)
        #expect(draft.order == [c.id, a.id, b.id])
    }

    @Test func theMediaAlreadyAtTheHeadOffersToPutTheMapBackFirst() {
        var draft = draft(mediaFirst: true)

        #expect(draft.actions(for: a.id) == [.putMapFirst, .remove])
        #expect(draft.actions(for: b.id) == [.putFirst, .remove])

        draft.putMapFirst()

        #expect(draft.slides.map(\.id) == [.map, .media(a.id), .media(b.id), .media(c.id)])
        #expect(draft.actions(for: a.id) == [.putFirst, .remove])
    }

    @Test func withoutAMapPuttingFirstOnlyMovesTheMediaToTheHead() {
        var draft = draft(hasMap: false)

        #expect(draft.actions(for: a.id) == [.remove])

        draft.putFirst(b.id)

        #expect(draft.slides.map(\.id) == [.media(b.id), .media(a.id), .media(c.id)])
        #expect(draft.actions(for: b.id) == [.remove])
    }

    @Test func theMapStaysFirstOrSecondWhateverTheAthleteDoes() {
        var generator = SeededGenerator(seed: 184)
        for _ in 0 ..< 200 {
            var draft = MediaDraft(media: [a, b, c], hasMap: true, mediaFirst: Bool.random(using: &generator))
            draft.add([MediaUploadHarness.photo(Data()), MediaUploadHarness.photo(Data())])
            for _ in 0 ..< 12 {
                guard let item = draft.items.randomElement(using: &generator) else { break }
                switch Int.random(in: 0 ..< 4, using: &generator) {
                case 0: draft.putFirst(item.id)
                case 1: draft.putMapFirst()
                case 2: draft.remove(item.id)
                default:
                    let from = Int.random(in: 0 ..< draft.count, using: &generator)
                    draft.move(fromOffsets: IndexSet(integer: from), toOffset: Int.random(in: 0 ... draft.count, using: &generator))
                }
                let mapIndex = draft.slides.firstIndex(of: .map)
                #expect(mapIndex == 0 || (mapIndex == 1 && draft.count > 0))
            }
        }
    }

    @Test func removingTheMediaBeforeTheMapPutsTheMapBackFirst() {
        var draft = draft(mediaFirst: true)

        draft.remove(a.id)

        #expect(draft.slides.map(\.id) == [.map, .media(b.id), .media(c.id)])
        #expect(draft.removed == [a])
        #expect(draft.remaining == 6)
    }

    @Test func aPickedMediaRemovedBeforeSavingIsNeitherQueuedNorCountedAsRemoved() {
        var draft = draft()
        let picked = MediaUploadHarness.photo(Data())
        draft.add([picked])

        draft.remove(picked.id)

        #expect(draft.queued.isEmpty)
        #expect(draft.removed.isEmpty)
        #expect(!draft.hasChanges)
    }

    @Test func theOrderListMovesTheMediaAndKeepsWhichOneGoesBeforeTheMap() {
        var draft = draft(mediaFirst: true)

        draft.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)

        #expect(draft.order == [c.id, a.id, b.id])
        #expect(draft.slides.map(\.id) == [.media(c.id), .map, .media(a.id), .media(b.id)])
        #expect(draft.canReorder)
        #expect(!MediaDraft(media: [a], hasMap: true, mediaFirst: false).canReorder)
    }

    @Test func aSessionThatComesBackToTheStartHasNoChanges() async {
        var draft = draft()

        draft.putFirst(b.id)
        draft.putMapFirst()
        draft.move(fromOffsets: IndexSet(integer: 0), toOffset: 2)

        #expect(draft.order == [a.id, b.id, c.id])
        #expect(!draft.hasChanges)
        #expect(await draft.saved() == nil)
    }

    @Test func theSavedEventCountsWhatTheSessionChanged() async throws {
        var draft = draft()
        draft.remove(b.id)
        draft.add([MediaUploadHarness.photo(Data()), MediaUploadHarness.photo(Data())])
        draft.putFirst(c.id)

        let saved = try #require(await draft.saved())
        #expect(saved == ActivityMediaSaved(
            photosAdded: 2, videosAdded: 0, videosTrimmed: 0, mediaRemoved: 1, mediaFirst: true, mediaCount: 4
        ))
        #expect(AnalyticsEvent.activityMediaSaved(entry: .edit, saved).properties == [
            "entry": "edit", "photosAdded": 2, "videosAdded": 0, "videosTrimmed": 0,
            "mediaRemoved": 1, "mediaFirst": true, "mediaCount": 4,
        ])
        #expect(AnalyticsEvent.activityMediaSaved(entry: .edit, saved).name == "activity_media_saved")
    }

    @Test func mediaFirstIsReportedFalseWithoutAMap() async {
        var draft = draft(hasMap: false)

        draft.putFirst(c.id)

        #expect(await draft.saved()?.mediaFirst == false)
    }
}

/// A deterministic `RandomNumberGenerator` (SplitMix64).
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
