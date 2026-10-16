import Foundation

/// What the celebration's map has loaded so far (ADR-032 §5).
struct CelebrationMapLoading: Equatable, Sendable {
    /// The style and the base map's tiles under the camera: a style restored from the cache
    /// offline, without its tiles, is not a map to show.
    var baseMapLoaded = false
    var styleFailed = false
    /// The terrain's elevation tiles under the camera.
    var terrainLoaded = false
    /// `CelebrationMapMode.loadingDeadline` has passed since the celebration appeared.
    var deadlinePassed = false
}

/// How the celebration plays its trace (ADR-032 §5): on the map in 3D with terrain, on a
/// top-down 2D map (terrain late), or without a map (style not ready in about 1 s, typically
/// offline). Pure: the view feeds it the map's load events.
enum CelebrationMapMode: Equatable, Sendable {
    /// Still loading: the no-map sketch shows, the map loads hidden over it.
    case pending
    case terrain3D
    case flat2D
    case noMap

    /// Past this, a base map not ready means no map, and terrain not ready means 2D.
    static let loadingDeadline: TimeInterval = 1

    /// The mode once `loading` is known. A chosen mode holds for the whole celebration: the
    /// background never switches mid-draw.
    func next(_ loading: CelebrationMapLoading) -> CelebrationMapMode {
        guard self == .pending else { return self }
        if loading.styleFailed { return .noMap }
        if loading.baseMapLoaded, loading.terrainLoaded { return .terrain3D }
        guard loading.deadlinePassed else { return .pending }
        return loading.baseMapLoaded ? .flat2D : .noMap
    }

    var showsMap: Bool {
        self == .terrain3D || self == .flat2D
    }

    var usesTerrain: Bool {
        self == .terrain3D
    }

    /// The camera's pitch while it follows the head: tilted over the terrain, or top-down.
    var followPitch: Double {
        usesTerrain ? 50 : 0
    }
}
