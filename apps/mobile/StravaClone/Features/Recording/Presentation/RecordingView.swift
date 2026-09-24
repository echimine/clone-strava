import SwiftUI

struct RecordingView: View {
    @State var store: RecordingStore

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.spacing) {
                Spacer()
                // TODO(ADR-002): Mapbox route map (MapboxMaps imported only in Presentation/).
                Text(distanceText)
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("km")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                if case .failed(let message) = store.state {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Spacer()
                Button {
                    Task { store.isRecording ? await store.stop() : await store.start() }
                } label: {
                    Text(store.isRecording ? "Arrêter" : "Démarrer")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(store.isRecording ? .red : Theme.accent)
            }
            .padding(Theme.spacing)
            .navigationTitle("Enregistrer")
        }
    }

    private var distanceText: String {
        guard case .recording(let recording) = store.state else { return "0.00" }
        return recording.distance.kilometers.formatted(.number.precision(.fractionLength(2)))
    }
}
