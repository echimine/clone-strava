import Foundation
import Testing
@testable import StravaClone

struct CelebrationMapModeTests {
    /// ADR-032 §5: the map plays in 3D once its base map and terrain are ready.
    @Test func baseMapAndTerrainReadyGiveThe3DMap() {
        let loading = CelebrationMapLoading(baseMapLoaded: true, terrainLoaded: true)

        #expect(CelebrationMapMode.pending.next(loading, reduceMotion: false) == .terrain3D)
    }

    /// The map waits, hidden over the no-map sketch, while the base map or the terrain loads.
    @Test func theMapWaitsWhileItLoads() {
        #expect(CelebrationMapMode.pending.next(CelebrationMapLoading(), reduceMotion: false) == .pending)
        #expect(CelebrationMapMode.pending.next(CelebrationMapLoading(baseMapLoaded: true), reduceMotion: false) == .pending)
        #expect(!CelebrationMapMode.pending.showsMap)
    }

    /// ADR-032 §5: terrain still loading at the deadline gives the top-down 2D map.
    @Test func terrainLateAtTheDeadlineGivesThe2DMap() {
        let loading = CelebrationMapLoading(baseMapLoaded: true, deadlinePassed: true)

        #expect(CelebrationMapMode.pending.next(loading, reduceMotion: false) == .flat2D)
    }

    /// ADR-032 §5: a base map not ready in about 1 s (no network) keeps the no-map celebration.
    @Test func baseMapNotReadyAtTheDeadlineGivesNoMap() {
        let loading = CelebrationMapLoading(terrainLoaded: true, deadlinePassed: true)

        #expect(CelebrationMapMode.pending.next(loading, reduceMotion: false) == .noMap)
        #expect(CelebrationMapMode.loadingDeadline == 1)
    }

    /// A style that fails to load does not wait for the deadline.
    @Test func aStyleErrorGivesNoMapAtOnce() {
        let loading = CelebrationMapLoading(styleFailed: true)

        #expect(CelebrationMapMode.pending.next(loading, reduceMotion: false) == .noMap)
    }

    /// ADR-032 §5: with Reduce Motion, the map is top-down and does not wait for the terrain.
    @Test func reduceMotionGivesThe2DMapAsSoonAsTheBaseMapIsReady() {
        let baseMapOnly = CelebrationMapLoading(baseMapLoaded: true)
        let everything = CelebrationMapLoading(baseMapLoaded: true, terrainLoaded: true)

        #expect(CelebrationMapMode.pending.next(baseMapOnly, reduceMotion: true) == .flat2D)
        #expect(CelebrationMapMode.pending.next(everything, reduceMotion: true) == .flat2D)
    }

    /// Once chosen, the mode holds for the whole celebration: no switch from sketch to map, or
    /// from 2D to 3D, in the middle of the draw.
    @Test func aChosenModeNeverChanges() {
        let everything = CelebrationMapLoading(baseMapLoaded: true, terrainLoaded: true, deadlinePassed: true)

        #expect(CelebrationMapMode.noMap.next(everything, reduceMotion: false) == .noMap)
        #expect(CelebrationMapMode.flat2D.next(everything, reduceMotion: false) == .flat2D)
        #expect(CelebrationMapMode.terrain3D.next(CelebrationMapLoading(styleFailed: true), reduceMotion: true) == .terrain3D)
    }

    /// The 3D mode is pitched with terrain; the 2D one is top-down.
    @Test func onlyThe3DMapIsPitched() {
        #expect(CelebrationMapMode.terrain3D.usesTerrain)
        #expect(CelebrationMapMode.terrain3D.followPitch > 45)
        #expect(!CelebrationMapMode.flat2D.usesTerrain)
        #expect(CelebrationMapMode.flat2D.followPitch == 0)
        #expect(CelebrationMapMode.flat2D.showsMap && CelebrationMapMode.terrain3D.showsMap)
        #expect(!CelebrationMapMode.noMap.showsMap)
    }
}
