import MapboxMaps
import SwiftUI

/// Pre-start screen (ADR-031 §2): full-screen map on the position (fitting the Itinerary once
/// chosen), sport and Itinerary chips, GPS indicator and a large "Démarrer". Location access is
/// asked the first time the tab opens; denied, a message and "Ouvrir Réglages" replace "Démarrer".
struct RecordingPreStartView: View {
    @Bindable var store: RecordingStore
    var onCreateItinerary: () -> Void = {}

    @Environment(LocationPermissionService.self) private var permission
    @State private var viewport = Viewport.followUser
    @State private var itineraryTrack: [Coordinate] = []

    private var isDenied: Bool {
        permission.authorization == .denied || permission.authorization == .restricted
    }

    var body: some View {
        AppMap(viewport: $viewport, bottomInset: 190) {
            ItineraryTrackLine(track: itineraryTrack)
        }
            .overlay(alignment: .top) {
                HStack {
                    RecordingGPSStatus()
                    Spacer()
                }
                .padding(.horizontal, Theme.spacing)
                .padding(.top, 8)
            }
            .safeAreaInset(edge: .bottom) { panel }
            .task { permission.requestWhenInUseIfNeeded() }
            // The cache changes behind this screen (sync, an Itinerary created or deleted elsewhere).
            .task {
                while !Task.isCancelled {
                    await store.loadItineraries()
                    try? await Task.sleep(for: .seconds(5))
                }
            }
            .task(id: store.chosenItinerary?.id) {
                itineraryTrack = await store.chosenItineraryTrack()
                viewport = itineraryTrack.count >= 2
                    ? .overview(
                        geometry: LineString(itineraryTrack.map(\.locationCoordinate)),
                        geometryPadding: EdgeInsets(top: 80, leading: 40, bottom: 260, trailing: 40)
                    )
                    : .followUser
            }
    }

    private var panel: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                sportPicker
                itineraryPicker
            }
            if store.offersAutoPause {
                RecordingAutoPauseToggle(store: store)
            }
            if let message = store.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            if isDenied {
                Text(RecordingMessages.locationDenied)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                Button("Ouvrir Réglages", action: permission.openSettings)
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Color(.secondarySystemFill), in: Capsule())
                    .buttonStyle(.plain)
            } else {
                Button {
                    Task { await store.start() }
                } label: {
                    Text("Démarrer")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(store.isBusy)
                .accessibilityIdentifier("recordingStartButton")
            }
        }
        .padding(Theme.spacing)
        .glassBackground(in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, Theme.spacing)
        .padding(.bottom, 8)
    }

    private var sportPicker: some View {
        Menu {
            Picker("Sport", selection: $store.sport) {
                ForEach(RecordingSport.allCases, id: \.self) { sport in
                    Label(RecordingFormatters.sportLabel(sport), systemImage: RecordingFormatters.sportSymbol(sport))
                        .tag(sport)
                }
            }
        } label: {
            Label(RecordingFormatters.sportLabel(store.sport), systemImage: RecordingFormatters.sportSymbol(store.sport))
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("recordingSportChip")
    }

    /// "Aucun" by default; every cached Itinerary, newest first; one without its track on the
    /// phone is listed but not selectable; none at all offers "Créer un Itinéraire".
    private var itineraryPicker: some View {
        Menu {
            Button {
                store.choose(nil)
            } label: {
                if store.chosenItinerary == nil {
                    Label(RecordingMessages.noItinerary, systemImage: "checkmark")
                } else {
                    Text(RecordingMessages.noItinerary)
                }
            }
            if store.itineraries.isEmpty {
                Button(RecordingMessages.createItinerary, systemImage: "plus", action: onCreateItinerary)
            }
            ForEach(store.itineraries) { listing in
                Button {
                    store.choose(listing)
                } label: {
                    if store.chosenItinerary?.id == listing.id {
                        Label(listing.name, systemImage: "checkmark")
                    } else {
                        Text(listing.name)
                    }
                    Text(listing.hasTrack ? ActivityFormatters.distance(listing.distance) : RecordingMessages.itineraryUnavailableOffline)
                }
                .disabled(!listing.hasTrack)
            }
        } label: {
            Label(store.chosenItinerary?.name ?? RecordingMessages.noItinerary, systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("recordingItineraryChip")
    }
}
