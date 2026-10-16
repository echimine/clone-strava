import MapboxMaps
import SwiftUI

/// The celebration's background on the real map (ADR-032 §5, #83). The map loads hidden over
/// the no-map sketch, which keeps drawing meanwhile; `CelebrationMapMode` then reveals it in 3D
/// with terrain, in top-down 2D (terrain late), or never (base map not ready in about 1 s): the
/// sketch then plays the whole celebration, as offline.
struct CelebrationMapBackground: View {
    let trace: [Coordinate]
    let frame: CelebrationFrame

    /// Built once: the background is redrawn on every frame of the celebration.
    @State private var route: CelebrationRoute?
    @State private var loading = CelebrationMapLoading()
    @State private var mode = CelebrationMapMode.pending

    var body: some View {
        ZStack {
            CelebrationSketchBackground(trace: trace, progress: frame.traceProgress)
                // Under the map until the count ends, long after the map faded in: past that,
                // the orange would show through the map as it fades out into the mini-map.
                .opacity(mode.showsMap && frame.milestone == .counted ? 0 : 1)
            if let route, mode != .noMap {
                CelebrationMap(route: route, frame: frame, mode: mode, loading: $loading)
                    .opacity(mode.showsMap ? 1 : 0)
                // The stats count up in white at the bottom: keep them readable over the map.
                LinearGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    startPoint: UnitPoint(x: 0.5, y: 0.55),
                    endPoint: .bottom
                )
                .opacity(mode.showsMap ? 1 : 0)
                .allowsHitTesting(false)
            }
        }
        .animation(.easeIn(duration: 0.25), value: mode)
        .onAppear { route = CelebrationRoute(trace: trace) }
        .task {
            try? await Task.sleep(for: .seconds(CelebrationMapMode.loadingDeadline))
            loading.deadlinePassed = true
        }
        .onChange(of: loading) { _, loading in
            mode = mode.next(loading)
        }
    }
}

/// The Mapbox map itself: the trace drawn by a trim on a line-metrics source, the camera on
/// the head of the simplified trace, then pulling back to frame the whole outing top-down,
/// north up, as the finish screen's mini-map does, which it then shrinks into.
private struct CelebrationMap: View {
    let route: CelebrationRoute
    let frame: CelebrationFrame
    let mode: CelebrationMapMode
    @Binding var loading: CelebrationMapLoading

    @State private var viewport = Viewport.idle
    @State private var size = CGSize.zero

    private static let traceID = "celebration-trace"
    private static let headID = "celebration-head"
    private static let demID = "celebration-dem"
    /// The vector source of `outdoors-v12`, the base map.
    private static let baseMapSourceID = "composite"

    /// Past the draw, the camera frames the outing.
    private var framesWholeOuting: Bool {
        frame.milestone >= .traceDrawn
    }

    var body: some View {
        Map(viewport: $viewport) {
            // Elevation loads with the style unless the 2D map was chosen.
            if mode != .flat2D {
                Self.demSource
                Terrain(sourceId: Self.demID).exaggeration(1.5)
            }
            Self.traceSource(route.trace.map(\.locationCoordinate))
            LineLayer(id: "celebration-trace-line", source: Self.traceID)
                .lineColor(UIColor(Theme.accent))
                .lineWidth(6)
                .lineCap(.round)
                .lineJoin(.round)
                // The part [start, end] is hidden: the trace is drawn up to `traceProgress`.
                .lineTrimOffset(start: frame.traceProgress, end: 1)
            if frame.traceProgress < 1, let head = route.head(at: frame.traceProgress) {
                GeoJSONSource(id: Self.headID)
                    .data(.feature(Feature(geometry: Point(head.locationCoordinate))))
                CircleLayer(id: "celebration-head-dot", source: Self.headID)
                    .circleRadius(7)
                    .circleColor(UIColor.white)
                    .circleStrokeColor(UIColor(Theme.accent))
                    .circleStrokeWidth(3)
            }
        }
        .mapStyle(.outdoors)
        .gestureOptions(.allDisabled)
        .ornamentOptions(OrnamentOptions(
            scaleBar: ScaleBarViewOptions(visibility: .hidden),
            compass: CompassViewOptions(visibility: .hidden)
        ))
        .onMapLoadingError { error in
            if error.type == .style { loading.styleFailed = true }
        }
        .onSourceDataLoaded { event in
            guard event.type == .tile, event.loaded == true else { return }
            switch event.sourceId {
            case Self.baseMapSourceID: loading.baseMapLoaded = true
            case Self.demID: loading.terrainLoaded = true
            default: break
            }
        }
        .onMapLoaded { _ in
            // Every visible tile is drawn, the elevation's too while it is declared.
            loading.baseMapLoaded = true
            if mode != .flat2D { loading.terrainLoaded = true }
        }
        // The celebration's tap (skip to the end) goes through the map.
        .allowsHitTesting(false)
        .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
        .onAppear { placeCamera() }
        .onChange(of: frame.traceProgress) { placeCamera() }
        .onChange(of: mode) { placeCamera() }
        .onChange(of: size) {
            // Shrinking into the mini-map: keep the whole outing framed.
            if framesWholeOuting { viewport = overview }
        }
        .onChange(of: frame.milestone) { _, milestone in
            guard milestone == .traceDrawn else { return }
            let pullBack = CelebrationTimeline.settlesAt - CelebrationTimeline.traceDrawnAt
            withViewportAnimation(.easeInOut(duration: pullBack)) { viewport = overview }
        }
    }

    /// While the trace draws, the camera sits on the head of the simplified trace.
    private func placeCamera() {
        guard !framesWholeOuting, let center = route.cameraCenter(at: frame.traceProgress) else { return }
        viewport = .camera(
            center: center.locationCoordinate,
            zoom: route.followZoom,
            bearing: 0,
            pitch: mode.followPitch
        )
    }

    /// Top-down and north up: what the mini-map shows. Full screen, room is kept at the bottom
    /// for the stats; at the mini-map's size, its own padding.
    private var overview: Viewport {
        let padding = size.height >= 400
            ? EdgeInsets(top: size.height * 0.12, leading: 32, bottom: size.height * 0.24, trailing: 32)
            : RecordingTraceMap.overviewPadding
        return .overview(geometry: LineString(route.trace.map(\.locationCoordinate)), geometryPadding: padding)
    }

    /// `line-trim-offset` needs the source's line metrics; there is no modifier for them.
    private static func traceSource(_ line: [CLLocationCoordinate2D]) -> GeoJSONSource {
        var source = GeoJSONSource(id: traceID).data(.feature(Feature(geometry: LineString(line))))
        source.lineMetrics = true
        return source
    }

    /// `outdoors-v12` has no terrain: the Mapbox elevation tiles are added for the 3D map.
    private static var demSource: RasterDemSource {
        var source = RasterDemSource(id: demID)
            .url("mapbox://mapbox.mapbox-terrain-dem-v1")
            .maxzoom(14)
        source.tileSize = 514
        return source
    }
}
