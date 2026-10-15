import SwiftUI

/// Finish screen (ADR-031 §11): full screen, left only through Save, Resume or Delete.
/// Mini-map and the sport's final stats, without a "provisional" label. Save is disabled
/// below the sport's minimum duration or with fewer than 2 points, with the explanation.
struct RecordingFinishView: View {
    let store: RecordingStore
    let snapshot: RecordingSnapshot
    /// Save, wired by the upload issue (#66); disabled while `nil`.
    var onSave: (() -> Void)?

    @State private var confirmsDelete = false

    private var finalStats: RecordingStats {
        snapshot.stats(at: snapshot.recording.endedAt ?? .now)
    }

    var body: some View {
        VStack(spacing: 20) {
            Label(
                RecordingFormatters.sportLabel(snapshot.recording.sport),
                systemImage: RecordingFormatters.sportSymbol(snapshot.recording.sport)
            )
            .font(.title3.weight(.bold))
            .padding(.top, 8)

            RecordingTraceMap(trace: snapshot.trace)
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 16))

            HStack(alignment: .top) {
                ForEach(RecordingFormatters.items(finalStats).filter { $0.label != "Vitesse" }) { item in
                    VStack(spacing: 2) {
                        Text(item.value).font(.title2.weight(.bold)).monospacedDigit()
                        Text(item.unit.isEmpty ? item.label : "\(item.label) (\(item.unit))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            Spacer()

            if let message = store.errorMessage {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
            if let blocker = snapshot.saveBlocker {
                Text(RecordingMessages.saveBlocker(blocker, sport: snapshot.recording.sport))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("recordingSaveBlocker")
            }
            Button {
                onSave?()
            } label: {
                Text("Enregistrer")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(onSave == nil || snapshot.saveBlocker != nil)
            .opacity(onSave == nil || snapshot.saveBlocker != nil ? 0.4 : 1)
            .accessibilityIdentifier("recordingSaveButton")

            HStack(spacing: 12) {
                Button("Reprendre") { Task { await store.reopen() } }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color(.secondarySystemFill), in: Capsule())
                    .accessibilityIdentifier("recordingReopenButton")
                Button("Supprimer", role: .destructive) { confirmsDelete = true }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color(.secondarySystemFill), in: Capsule())
                    .accessibilityIdentifier("recordingDeleteButton")
            }
            .font(.headline)
            .buttonStyle(.plain)
        }
        .padding(Theme.spacing)
        .interactiveDismissDisabled()
        .confirmationDialog(RecordingMessages.deleteTitle, isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) { Task { await store.delete() } }
        } message: {
            Text(RecordingMessages.deleteMessage)
        }
    }
}
