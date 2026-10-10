import MapboxMaps
import SwiftUI

/// Map tab (ADR-027 §6): follows the user from the start. Without location permission,
/// falls back to Paris and offers to open Settings. "Créer" starts a new Itinerary
/// (ADR-030); the editor belongs to another feature, so the action is injected.
/// MapboxMaps reads the access token from `MBXAccessToken` (Info.plist).
struct MapScreen: View {
    var onCreateItinerary: () -> Void = {}

    private static let fallbackCamera = Viewport.camera(
        center: CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522),
        zoom: 12
    )

    @Environment(LocationPermissionService.self) private var permission
    @State private var viewport: Viewport = .followUser

    private var isLocationBlocked: Bool {
        permission.authorization == .denied || permission.authorization == .restricted
    }

    var body: some View {
        // Identifier on the map only: on the whole screen it would hide the overlay's.
        AppMap(viewport: $viewport) {}
            .accessibilityIdentifier("mapScreen")
            .overlay(alignment: .top) {
                VStack(alignment: .trailing, spacing: 8) {
                    if isLocationBlocked {
                        locationBanner
                    }
                    createItineraryButton
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .onChange(of: isLocationBlocked, initial: true) { _, blocked in
                if blocked {
                    viewport = Self.fallbackCamera
                }
            }
    }

    private var createItineraryButton: some View {
        Button(action: onCreateItinerary) {
            Label("Créer", systemImage: "plus")
                .font(.subheadline.bold())
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .shadow(radius: 2)
        }
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, Theme.spacing)
        .padding(.top, 8)
        .accessibilityLabel("Créer un Itinéraire")
        .accessibilityIdentifier("createItineraryButton")
    }

    private var locationBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "location.slash")
            Text("Autorisez la localisation pour voir votre position.")
                .font(.footnote)
            Spacer(minLength: 0)
            Button("Réglages", action: permission.openSettings)
                .font(.footnote.bold())
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, Theme.spacing)
        .padding(.top, 8)
        .accessibilityIdentifier("locationPermissionBanner")
    }
}
