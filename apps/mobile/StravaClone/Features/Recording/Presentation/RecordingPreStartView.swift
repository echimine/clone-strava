import MapboxMaps
import SwiftUI

/// Pre-start screen (ADR-031 §2): full-screen map on the position, sport chip, GPS indicator
/// and a large "Démarrer". Location access is asked the first time the tab opens; denied, a
/// message and "Ouvrir Réglages" replace "Démarrer".
struct RecordingPreStartView: View {
    @Bindable var store: RecordingStore

    @Environment(LocationPermissionService.self) private var permission
    @State private var viewport = Viewport.followUser

    private var isDenied: Bool {
        permission.authorization == .denied || permission.authorization == .restricted
    }

    var body: some View {
        AppMap(viewport: $viewport, bottomInset: 190) {}
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
    }

    private var panel: some View {
        VStack(spacing: 14) {
            sportPicker
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
}
