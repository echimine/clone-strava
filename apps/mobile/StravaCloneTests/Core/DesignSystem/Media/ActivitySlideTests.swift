import Foundation
import Testing
@testable import StravaClone

/// The carousel's order (ADR-037 §7, §8): the map, then the Media; or the first Media, the
/// map, then the rest. `mediaFirst` does nothing without a map or without Media.
struct ActivitySlideTests {
    private struct Media: Identifiable, Hashable {
        let id: String
    }

    private let a = Media(id: "a")
    private let b = Media(id: "b")
    private let c = Media(id: "c")

    @Test func mapOnly() {
        #expect(ActivitySlide.compose(hasMap: true, media: [Media](), mediaFirst: false) == [.map])
    }

    @Test func mediaFirstIsIgnoredWithoutMedia() {
        #expect(ActivitySlide.compose(hasMap: true, media: [Media](), mediaFirst: true) == [.map])
    }

    @Test func oneMediaWithoutMap() {
        #expect(ActivitySlide.compose(hasMap: false, media: [a], mediaFirst: false) == [.media(a)])
    }

    @Test func theMapComesBeforeTheMedia() {
        #expect(
            ActivitySlide.compose(hasMap: true, media: [a, b, c], mediaFirst: false)
                == [.map, .media(a), .media(b), .media(c)]
        )
    }

    @Test func mediaFirstPutsTheFirstMediaBeforeTheMap() {
        #expect(
            ActivitySlide.compose(hasMap: true, media: [a, b, c], mediaFirst: true)
                == [.media(a), .map, .media(b), .media(c)]
        )
    }

    @Test func withoutMapTheCarouselStartsWithTheFirstMedia() {
        #expect(ActivitySlide.compose(hasMap: false, media: [a, b], mediaFirst: true) == [.media(a), .media(b)])
        #expect(ActivitySlide.compose(hasMap: false, media: [a, b], mediaFirst: false) == [.media(a), .media(b)])
    }

    @Test func noMapAndNoMediaHasNoSlide() {
        #expect(ActivitySlide.compose(hasMap: false, media: [Media](), mediaFirst: false).isEmpty)
    }

    @Test func slideIdentitiesAreStable() {
        #expect(ActivitySlide<Media>.map.id == .map)
        #expect(ActivitySlide.media(a).id == .media("a"))
    }
}
