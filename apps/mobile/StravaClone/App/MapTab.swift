import SwiftUI

/// The Map tab (ADR-039 §15, amends ADR-030): its two modes, composed by the app shell since
/// each belongs to another feature (ADR-007 rule 5). « Itinéraires » shows my Itineraries'
/// carousel; « Segments » the Segments of the zone, their paths in grey and their carousel.
/// The stack pushes an Itinerary's detail, a Segment's sheet and every `AppDestinations` screen.
struct MapTab: View {
    @Binding var path: NavigationPath
    let itineraries: MapItinerariesStore
    let segments: SegmentMapStore
    let destinations: AppDestinations
    let onCreateItinerary: () -> Void

    @State private var mode = MapMode.itineraries
    /// The last camera at rest, so the Segments mode opens on the zone shown.
    @State private var camera: MapArea?

    var body: some View {
        NavigationStack(path: $path) {
            MapScreen(
                mode: $mode,
                onCreateItinerary: onCreateItinerary,
                focusedPath: mode == .segments ? segments.focusedPath : itineraries.focusedPath,
                paths: segmentPaths,
                onPathTapped: { id in withAnimation(.snappy) { segments.focusedID = id } },
                onCameraSettled: { area in
                    camera = area
                    if mode == .segments {
                        Task { await segments.cameraSettled(area) }
                    }
                },
                top: {
                    if mode == .segments {
                        SegmentMapControls(store: segments)
                    }
                },
                bottom: {
                    switch mode {
                    case .itineraries:
                        MapItinerariesCarousel(store: itineraries)
                    case .segments:
                        SegmentMapCarousel(store: segments) { id in
                            path.append(SegmentRequest(segmentID: id))
                        }
                    }
                }
            )
            .onChange(of: mode) { _, mode in
                // The zone shown when the mode opens, if the map has settled already.
                if mode == .segments, let camera {
                    Task { await segments.cameraSettled(camera) }
                }
            }
            .navigationDestination(for: ItineraryID.self) { [itineraries] id in
                ItineraryDetailPage(
                    id: id,
                    makeDetailStore: itineraries.makeDetailStore,
                    makeEditFlow: itineraries.makeEditFlow
                )
            }
            .registerAppDestinations(destinations)
        }
    }

    /// The zone's Segments in grey, the highlighted one apart (drawn in orange).
    private var segmentPaths: [MapPath] {
        guard mode == .segments else { return [] }
        return segments.visibleSegments
            .filter { $0.id != segments.focusedID }
            .map { MapPath(id: $0.id, coordinates: $0.path) }
    }
}
