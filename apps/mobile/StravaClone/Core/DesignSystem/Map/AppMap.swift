import MapboxMaps
import SwiftUI

/// Shared map of every map screen (ADR-027 §4): Outdoors style, user puck fed by the
/// app's single GPS source, recenter button. Screens add their own content (trace,
/// route, markers) through the `@MapContentBuilder` closure. `bottomInset` is the height
/// of what covers the bottom of the map (a carousel): the camera, the Mapbox ornaments and the
/// recenter button stay above it. `onCameraSettled`, if any, is told what the map shows each
/// time its camera comes to rest.
struct AppMap<Content: MapContent>: View {
    @Binding var viewport: Viewport
    var showsUserLocation = true
    var bottomInset: CGFloat = 0
    var onCameraSettled: (@MainActor (MapArea) -> Void)?
    @MapContentBuilder let content: () -> Content

    @Environment(\.locationProvider) private var locationProvider
    @Environment(LocationPermissionService.self) private var permission
    @State private var bridge = MapboxLocationBridge()

    init(
        viewport: Binding<Viewport>,
        showsUserLocation: Bool = true,
        bottomInset: CGFloat = 0,
        onCameraSettled: (@MainActor (MapArea) -> Void)? = nil,
        @MapContentBuilder content: @escaping () -> Content
    ) {
        _viewport = viewport
        self.showsUserLocation = showsUserLocation
        self.bottomInset = bottomInset
        self.onCameraSettled = onCameraSettled
        self.content = content
    }

    private var tracksUser: Bool {
        showsUserLocation && locationProvider != nil && permission.isAuthorized
    }

    var body: some View {
        // Full screen: the map runs under the status bar and the floating tab bar,
        // while the controls stay inside the safe area.
        ZStack(alignment: .bottomTrailing) {
            // Only with a listener: a screen's own `MapReader` around `AppMap` (the editor) must
            // keep reaching this map.
            if onCameraSettled != nil {
                MapReader { proxy in map(proxy) }
            } else {
                map(nil)
            }

            if tracksUser && viewport.followPuck == nil {
                recenterButton
            }
        }
        .task(id: tracksUser) {
            guard tracksUser, let locationProvider else { return }
            await bridge.run(provider: locationProvider)
        }
        .task {
            if showsUserLocation {
                permission.requestWhenInUseIfNeeded()
            }
        }
    }

    private func map(_ proxy: MapProxy?) -> some View {
        Map(viewport: $viewport) {
            if tracksUser {
                Puck2D(bearing: .heading)
                    .showsAccuracyRing(true)
            }
            content()
        }
        .mapStyle(.outdoors)
        .locationDataModel(bridge.dataModel)
        .onMapIdle { _ in
            guard let onCameraSettled, let map = proxy?.map else { return }
            let state = map.cameraState
            let bounds = map.coordinateBounds(for: CameraOptions(cameraState: state))
            onCameraSettled(MapArea(
                southWest: Coordinate(bounds.southwest),
                northEast: Coordinate(bounds.northeast),
                zoom: state.zoom
            ))
        }
        .additionalSafeAreaInsets(.bottom, bottomInset)
        .ignoresSafeArea()
    }

    private var recenterButton: some View {
        Button {
            withViewportAnimation {
                viewport = .followUser
            }
        } label: {
            Image(systemName: "location.fill")
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
                .glassBackground(in: Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        .padding(Theme.spacing)
        .padding(.bottom, bottomInset)
        .accessibilityLabel("Recentrer sur ma position")
        .accessibilityIdentifier("recenterButton")
    }
}

extension Viewport {
    /// Camera following the user puck, shared by map screens and the recenter button.
    static var followUser: Viewport { .followPuck(zoom: 15) }
}
