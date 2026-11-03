import ImageIO
import PhotosUI
import SwiftUI

/// "Photos et vidéos" (ADR-037 §10), in the edit sheet's `Form` (and the finish screen, #185):
/// a "5/8" counter and a horizontal strip, the map (a wider tile labelled "Carte"), the Media in
/// carousel order with their `thumbURL`, then "Ajouter photos/vidéo", a `PhotosPicker` with an
/// ordered selection limited to what remains; greyed at 8/8 ("Limite de 8 atteinte"). A tap on
/// a Media offers "Mettre en premier" (or "Remettre la carte en premier") and "Supprimer";
/// "Modifier l'ordre" (from 2 Media) opens a list with handles. A failed tile offers
/// "Réessayer" and "Retirer".
struct MediaManagementSection: View {
    @Binding var draft: MediaDraft
    let route: EncodedPolyline?
    let sport: SportType

    @State private var picked: [PhotosPickerItem] = []
    @State private var failedTile: ActivityMedia?
    @State private var actionTarget: MediaDraft.Item?
    @State private var reorders = false
    @Environment(\.mediaUploads) private var uploads

    var body: some View {
        Section {
            strip
            if draft.canReorder {
                Button(MediaUploadMessages.reorder) { reorders = true }
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("mediaSection.reorder")
            }
        } header: {
            HStack {
                Text(MediaUploadMessages.sectionTitle)
                Spacer()
                Text(MediaUploadMessages.counter(draft.count, limit: MediaDraft.limit))
                    .monospacedDigit()
                    .foregroundStyle(draft.remaining == 0 ? Color.red : .secondary)
                    .accessibilityIdentifier("mediaSection.counter")
            }
        } footer: {
            if draft.count > 0 {
                Text(MediaUploadMessages.tapHint)
            }
        }
    }

    /// The strip, one row of the section; the menus hang on it (a modifier on a `Section`
    /// would go to each of its rows).
    private var strip: some View {
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
        .confirmationDialog(
            MediaUploadMessages.mediaTitle,
            isPresented: Binding(get: { actionTarget != nil }, set: { if !$0 { actionTarget = nil } }),
            presenting: actionTarget
        ) { item in
            ForEach(draft.actions(for: item.id), id: \.self) { action in
                switch action {
                case .putFirst:
                    Button(MediaUploadMessages.putFirst) { draft.putFirst(item.id) }
                case .putMapFirst:
                    Button(MediaUploadMessages.putMapFirst) { draft.putMapFirst() }
                case .remove:
                    Button(MediaUploadMessages.delete, role: .destructive) { draft.remove(item.id) }
                }
            }
        }
        .sheet(isPresented: $reorders) {
            MediaOrderSheet(draft: $draft)
        }
        .background {
            // A second dialog on its own view: two on the same view can step on each other.
            Color.clear.confirmationDialog(
                MediaUploadMessages.failed,
                isPresented: Binding(get: { failedTile != nil }, set: { if !$0 { failedTile = nil } }),
                presenting: failedTile
            ) { media in
                if case .failed(_, true) = media.upload {
                    Button(MediaUploadMessages.retry) { uploads?.retry(media.id) }
                }
                Button(MediaUploadMessages.remove, role: .destructive) {
                    uploads?.remove(media.id)
                    draft.discard(media.id)
                }
            } message: { media in
                if case .failed(let reason, _) = media.upload {
                    Text(MediaUploadMessages.failure(reason))
                }
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
            .overlay {
                if let upload = media.upload {
                    MediaUploadOverlay(mediaID: media.id, status: upload, compact: true)
                        .clipShape(.rect(cornerRadius: 8))
                }
            }
            .contentShape(.rect)
            .onTapGesture {
                if case .failed = media.upload { failedTile = media } else { actionTarget = .existing(media) }
            }
            .accessibilityIdentifier("mediaSection.media")
        case .media(.added(let media)):
            PickedMediaPreview(media: media)
                .frame(width: Self.tileWidth, height: Self.tileHeight)
                .clipShape(.rect(cornerRadius: 8))
                .contentShape(.rect)
                .onTapGesture { actionTarget = .added(media) }
                .accessibilityIdentifier("mediaSection.added")
        }
    }

    private var addTile: some View {
        let remaining = draft.remaining
        return PhotosPicker(
            selection: $picked,
            maxSelectionCount: max(remaining, 1),
            selectionBehavior: .ordered,
            matching: .images,
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
            draft.add(items.map(PickedMedia.init(photo:)))
            picked = []
        }
    }

    private nonisolated static let tileWidth: CGFloat = 100
    private nonisolated static let tileHeight: CGFloat = 110
}

extension PickedMedia {
    /// A photo of the library, read only when exported (a Live Photo gives its key still).
    init(photo item: PhotosPickerItem) {
        self.init(source: MediaSource(kind: .photo) {
            guard let data = try await item.loadTransferable(type: Data.self) else { throw MediaExporter.Failure.failed }
            return .image(data)
        })
    }
}

/// A picked photo before "Enregistrer": decoded small from the library original.
struct PickedMediaPreview: View {
    let media: PickedMedia
    @State private var image: UIImage?

    var body: some View {
        Color(.tertiarySystemFill)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipped()
            .task(id: media.id) {
                image = await Self.thumbnail(of: media.source)
            }
    }

    private static func thumbnail(of source: MediaSource) async -> UIImage? {
        guard case .image(let data)? = try? await source.load(),
              let imageSource = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 256,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options).map(UIImage.init(cgImage:))
    }
}
