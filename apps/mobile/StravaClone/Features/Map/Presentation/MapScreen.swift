import MapboxMaps
import SwiftUI

/// Map tab. MapboxMaps reads the access token from `MBXAccessToken` (Info.plist).
struct MapScreen: View {
    @State private var viewport: Viewport = .camera(
        center: CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522),
        zoom: 12
    )

    var body: some View {
        Map(viewport: $viewport)
            .mapStyle(.outdoors)
            .ignoresSafeArea(edges: .top)
            .accessibilityIdentifier("mapScreen")
    }
}
