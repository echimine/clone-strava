import PhotosUI
import SwiftUI

/// "Photos et vidéos" (ADR-037 §10), in the edit sheet's `Form` (and the finish screen, #185):
/// a "5/8" counter and a horizontal strip, the map (a wider tile labelled "Carte"), the Media in
/// carousel order with their `thumbURL`, then "Ajouter photos/vidéo", a `PhotosPicker` with an
/// ordered selection limited to what remains; greyed at 8/8 ("Limite de 8 atteinte"). A failed
/// tile offers "Réessayer" and "Retirer".
struct MediaManagementSection: View {
    @Binding var draft: MediaDraft
    let route: EncodedPolyline?
    let sport: SportType

    @State private var picked: [PhotosPickerItem] = []
    @State private var failedTile: ActivityMedia?
    @Environment(\.mediaUploads) private var uploads

    var body: some View {
        Section {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(draft.slides) { slide in
                        tile(slide)
                    }
                    addTile
                }
            }
            .scrollIndicators(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        } header: {
            HStack {
                Text(MediaUploadMessages.sectionTitle)
                Spacer()
                Text(MediaUploadMessages.counter(draft.count, limit: MediaDraft.limit))
                    .monospacedDigit()
                    .foregroundStyle(draft.remaining == 0 ? Color.red : .secondary)
                    .accessibilityIdentifier("mediaSection.counter")
            }
        }
        .confirmationDialog(
            MediaUploadMessages.failed,
            isPresented: Binding(get: { failedTile != nil }, set: { if !$0 { failedTile = nil } }),
            presenting: failedTile
        ) { media in
            if case .failed(_, true) = media.upload {
                Button(MediaUploadMessages.retry) { uploads?.retry(media.id) }
            }
            Button(MediaUploadMessages.remove, role: .destructive) { uploads?.remove(media.id) }
        } message: { media in
            if case .failed(let reason, _) = media.upload {
                Text(MediaUploadMessages.failure(reason))
            }
        }
    }

    @ViewBuilder private func tile(_ slide: ActivitySlide<MediaDraft.Item>) -> some View {
        switch slide {
        case .map:
            ActivityMapImage(route: route, sport: sport, height: Self.tileHeight)
                .frame(width: 150, height: Self.tileHeight)
                .clipShape(.rect(cornerRadius: 8))
                .overlay(alignment: .bottomLeading) {
                    Label(MediaUploadMessages.map, systemImage: "map")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(5)
                }
                .accessibilityIdentifier("mediaSection.map")
        case .media(.existing(let media)):
            RemoteImage(url: media.upload == .exporting ? nil : media.thumbURL, maxPixelSize: 256) {
                Color(.tertiarySystemFill)
            }
            .frame(width: Self.tileWidth, height: Self.tileHeight)
            .clipShape(.rect(cornerRadius: 8))
            .overlay(alignment: .topTrailing) {
                if let duration = media.duration { VideoDurationBadge(duration: duration) }
            }
            .overlay {
                if let upload = media.upload {
                    MediaUploadOverlay(mediaID: media.id, status: upload, compact: true)
                        .clipShape(.rect(cornerRadius: 8))
                }
            }
            .contentShape(.rect)
            .onTapGesture {
                if case .failed = media.upload { failedTile = media }
            }
            .accessibilityIdentifier("mediaSection.media")
        case .media(.added(let media)):
            PickedMediaPreview(media: media)
                .frame(width: Self.tileWidth, height: Self.tileHeight)
                .clipShape(.rect(cornerRadius: 8))
                .accessibilityIdentifier("mediaSection.added")
        }
    }

    private var addTile: some View {
        let remaining = draft.remaining
        return PhotosPicker(
            selection: $picked,
            maxSelectionCount: max(remaining, 1),
            selectionBehavior: .ordered,
            matching: .any(of: [.images, .videos]),
            photoLibrary: .shared()
        ) {
            VStack(spacing: 6) {
                Image(systemName: remaining == 0 ? "photo.badge.exclamationmark" : "photo.badge.plus")
                    .font(.title3)
                Text(remaining == 0 ? MediaUploadMessages.limitReached : MediaUploadMessages.add)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
            .padding(6)
            .frame(width: 110, height: Self.tileHeight)
            .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 8))
            .foregroundStyle(remaining == 0 ? Color.secondary : Color.primary)
        }
        .buttonStyle(.plain)
        .disabled(remaining == 0)
        .accessibilityIdentifier("mediaSection.add")
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            draft.add(items.map(PickedMedia.init(item:)))
            picked = []
        }
    }

    private nonisolated static let tileWidth: CGFloat = 100
    private nonisolated static let tileHeight: CGFloat = 110
}
