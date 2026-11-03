import SwiftUI

/// "Modifier l'ordre" (ADR-037 §10): the Media alone, in a list with handles. The map is not
/// listed: it stays before the Media, or right after the first one (`mediaFirst`).
struct MediaOrderSheet: View {
    @Binding var draft: MediaDraft
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(draft.items) { item in
                    row(item)
                }
                .onMove { source, destination in
                    draft.move(fromOffsets: source, toOffset: destination)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(MediaUploadMessages.orderTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(MediaUploadMessages.done) { dismiss() }
                        .accessibilityIdentifier("mediaOrder.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ item: MediaDraft.Item) -> some View {
        HStack(spacing: 12) {
            thumbnail(item)
                .frame(width: 52, height: 52)
                .clipShape(.rect(cornerRadius: 6))
            VStack(alignment: .leading) {
                Text(kind(of: item) == .video ? MediaUploadMessages.video : MediaUploadMessages.photo)
                if case .existing(let media) = item, let duration = media.duration {
                    Text(ActivityMediaSlide.durationLabel(duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("mediaOrder.row")
    }

    @ViewBuilder private func thumbnail(_ item: MediaDraft.Item) -> some View {
        switch item {
        case .existing(let media):
            RemoteImage(url: media.upload == .exporting ? nil : media.thumbURL, maxPixelSize: 128) {
                Color(.tertiarySystemFill)
            }
        case .added(let picked):
            PickedMediaPreview(media: picked)
        }
    }

    private func kind(of item: MediaDraft.Item) -> ActivityMedia.Kind {
        switch item {
        case .existing(let media): media.kind
        case .added(let picked): picked.kind
        }
    }
}
