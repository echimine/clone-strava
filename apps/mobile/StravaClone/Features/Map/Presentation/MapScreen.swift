import MapboxMaps
import SwiftUI

/// The two modes of the Map tab (ADR-039 §15, amends ADR-030), selector top left.
enum MapMode: String, CaseIterable, Hashable {
    case itineraries = "Itinéraires"
    case segments = "Segments"
}

/// Map tab (ADR-027 §6): follows the user from the start. Without location permission,
/// falls back to Paris and offers to open Settings. Two modes, « Itinéraires | Segments »
/// (ADR-039 §15); "Créer", top right in both, starts a new Itinerary (ADR-030). What each mode
/// shows belongs to other features, so it is injected: controls under the mode selector (`top`),
/// grey tappable `paths`, the bottom content (the Itineraries or Segments carousel) with the path
/// it wants framed above it, and a listener of the camera. It sits in a navigation stack, so what
/// it pushes covers the map. MapboxMaps reads the access token from `MBXAccessToken` (Info.plist).
struct MapScreen<Top: View, Bottom: View>: View {
    @Binding var mode: MapMode
    var onCreateItinerary: () -> Void = {}
    /// Path drawn in orange and framed on the map (the card centred in the carousel), if any.
    var focusedPath: [Coordinate]?
    /// Paths drawn in dark grey under the focused one.
    var paths: [MapPath] = []
    var onPathTapped: (String) -> Void = { _ in }
    var onCameraSettled: (@MainActor (MapArea) -> Void)?
    @ViewBuilder var top: () -> Top
    @ViewBuilder var bottom: () -> Bottom

    private static var fallbackCamera: Viewport {
        .camera(center: CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522), zoom: 12)
    }

    @Environment(LocationPermissionService.self) private var permission
    @State private var viewport: Viewport = .followUser
    @State private var bottomHeight: CGFloat = 0
    @State private var topHeight: CGFloat = 0

    private var isLocationBlocked: Bool {
        permission.authorization == .denied || permission.authorization == .restricted
    }

    var body: some View {
        // Identifier on the map only: on the whole screen it would hide the overlays'.
        AppMap(viewport: $viewport, bottomInset: bottomHeight, onCameraSettled: onCameraSettled) {
            MapPathsContent(paths: paths, onTap: onPathTapped)
            if let focusedPath, focusedPath.count >= 2 {
                FocusedPathContent(coordinates: focusedPath.map(\.locationCoordinate))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Carte")
        .accessibilityValue(focusedPathDescription)
        .accessibilityIdentifier("mapScreen")
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if isLocationBlocked {
                    locationBanner
                }
                HStack(alignment: .center) {
                    modePicker
                    Spacer(minLength: 8)
                    createItineraryButton
                }
                .padding(.horizontal, Theme.spacing)
                .padding(.top, 8)
                top()
            }
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { topHeight = $0 }
        }
        .overlay(alignment: .bottom) {
            bottom()
                .padding(.bottom, 8)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { bottomHeight = $0 }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: isLocationBlocked, initial: true) { _, blocked in
            if blocked {
                viewport = Self.fallbackCamera
            }
        }
        .onChange(of: focusedPath) { _, path in
            guard let path, path.count >= 2 else { return }
            withViewportAnimation(.easeOut(duration: 0.6)) {
                viewport = .overview(
                    geometry: LineString(path.map(\.locationCoordinate)),
                    geometryPadding: EdgeInsets(top: topHeight + 24, leading: 40, bottom: 32, trailing: 40)
                )
            }
        }
    }

    private var focusedPathDescription: String {
        guard let focusedPath, focusedPath.count >= 2 else { return "" }
        return mode == .segments ? "Segment sélectionné tracé sur la carte" : "Itinéraire sélectionné tracé sur la carte"
    }

    private var modePicker: some View {
        Picker("Mode de la carte", selection: $mode.animation()) {
            ForEach(MapMode.allCases, id: \.self) { Text($0.rawValue) }
        }
        .pickerStyle(.segmented)
        .frame(width: 220)
        .padding(4)
        .glassBackground(in: Capsule())
        .accessibilityIdentifier("mapModePicker")
    }

    private var createItineraryButton: some View {
        Button(action: onCreateItinerary) {
            Label("Créer", systemImage: "plus")
                .font(.subheadline.bold())
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Capsule())
                .glassBackground(in: Capsule(), interactive: true)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.accent)
        .accessibilityLabel("Créer un Itinéraire")
        .accessibilityIdentifier("createItineraryButton")
    }

    private var locationBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "location.slash")
                .accessibilityHidden(true)
            Text("Autorisez la localisation pour voir votre position.")
                .font(.footnote)
            Spacer(minLength: 0)
            Button("Réglages", action: permission.openSettings)
                .font(.footnote.bold())
                .accessibilityLabel("Ouvrir les Réglages")
        }
        .padding(12)
        .glassBackground(in: .rect(cornerRadius: 12))
        .padding(.horizontal, Theme.spacing)
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("locationPermissionBanner")
        .onAppear {
            AccessibilityNotification.Announcement("Autorisez la localisation pour voir votre position.").post()
        }
    }
}

/// The framed path: an orange line with its start and finish markers.
private struct FocusedPathContent: MapContent {
    let coordinates: [CLLocationCoordinate2D]

    var body: some MapContent {
        PolylineAnnotation(lineCoordinates: coordinates)
            .lineColor(UIColor(Theme.accent))
            .lineWidth(5)
            .lineJoin(.round)
        RouteEndpointsContent(coordinates: coordinates)
    }
}
