import MapboxMaps
import SwiftUI

/// Shared map of every map screen (ADR-027 §4): Outdoors style, user puck fed by the
/// app's single GPS source, recenter button. Screens add their own content (trace,
/// route, markers) through the `@MapContentBuilder` closure.
struct AppMap<Content: MapContent>: View {
    @Binding var viewport: Viewport
    var showsUserLocation = true
    @MapContentBuilder let content: () -> Content

    @Environment(\.locationProvider) private var locationProvider
    @Environment(LocationPermissionService.self) private var permission
    @State private var bridge = MapboxLocationBridge()

    init(
        viewport: Binding<Viewport>,
        showsUserLocation: Bool = true,
        @MapContentBuilder content: @escaping () -> Content
    ) {
        _viewport = viewport
        self.showsUserLocation = showsUserLocation
        self.content = content
    }

    private var tracksUser: Bool {
        showsUserLocation && locationProvider != nil && permission.isAuthorized
    }

    var body: some View {
        // Full screen: the map runs under the status bar and the floating tab bar,
        // while the controls stay inside the safe area.
        ZStack(alignment: .bottomTrailing) {
            Map(viewport: $viewport) {
                if tracksUser {
                    Puck2D(bearing: .heading)
                        .showsAccuracyRing(true)
                }
                content()
            }
            .mapStyle(.outdoors)
            .locationDataModel(bridge.dataModel)
            .ignoresSafeArea()

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
                .background(.regularMaterial, in: Circle())
                .shadow(radius: 2)
        }
        .padding(Theme.spacing)
        .accessibilityLabel("Recentrer sur ma position")
        .accessibilityIdentifier("recenterButton")
    }
}

extension Viewport {
    /// Camera following the user puck, shared by map screens and the recenter button.
    static var followUser: Viewport { .followPuck(zoom: 15) }
}
