import PhotosUI
import SwiftUI

/// "Photos et vidéos" (ADR-037 §10), in the edit sheet's `Form` and on the finish screen (plain):
/// a "5/8" counter and a horizontal strip, the map (a wider tile labelled "Carte"), the Media in
/// carousel order with their `thumbURL`, then "Ajouter photos/vidéo", a `PhotosPicker` with an
/// ordered selection limited to what remains; greyed at 8/8 ("Limite de 8 atteinte"). A tap on
/// a Media offers "Mettre en premier" (or "Remettre la carte en premier") and "Supprimer";
/// "Modifier l'ordre" (from 2 Media) opens a list with handles. A failed tile offers
/// "Réessayer" and "Retirer". On the finish screen, a Media is exported from its selection: a
/// failed export offers the same, an original the library could not hand offline shows "Média
/// indisponible hors connexion" with "Retirer" only (ADR-037 §6).
struct MediaManagementSection: View {
    enum Style {
        /// A `Section` of the edit sheet's `Form`.
        case form
        /// Outside a `Form` (the finish screen).
        case plain
    }

    @Binding var draft: MediaDraft
    let route: EncodedPolyline?
    let sport: SportType
    var style: Style = .form

    @State private var picked: [PhotosPickerItem] = []
    @State private var failedTile: ActivityMedia?
    @State private var failedPick: PickedMedia?
    @State private var actionTarget: MediaDraft.Item?
    @State private var reorders = false
    @Environment(\.mediaUploads) private var uploads

    var body: some View {
        switch style {
        case .form:
            Section {
                strip
                reorderButton
            } header: {
                header
            } footer: {
                footer
            }
        case .plain:
            VStack(alignment: .leading, spacing: 8) {
                header.font(.subheadline.weight(.semibold))
                strip
                HStack(alignment: .firstTextBaseline) {
                    footer.font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    reorderButton
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text(MediaUploadMessages.sectionTitle)
            Spacer()
            Text(MediaUploadMessages.counter(draft.count, limit: MediaDraft.limit))
                .monospacedDigit()
                .foregroundStyle(draft.remaining == 0 ? Color.red : .secondary)
                .accessibilityIdentifier("mediaSection.counter")
        }
    }

    @ViewBuilder private var footer: some View {
        if draft.count > 0 {
            Text(MediaUploadMessages.tapHint)
        }
    }

    @ViewBuilder private var reorderButton: some View {
        if draft.canReorder {
            Button(MediaUploadMessages.reorder) { reorders = true }
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("mediaSection.reorder")
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
        .background {
            Color.clear.confirmationDialog(
                MediaUploadMessages.failed,
                isPresented: Binding(get: { failedPick != nil }, set: { if !$0 { failedPick = nil } }),
                presenting: failedPick
            ) { media in
                if uploads?.preparation(of: media.id) == .failed {
                    Button(MediaUploadMessages.retry) { uploads?.retry(media.id) }
                }
                Button(MediaUploadMessages.remove, role: .destructive) { draft.discard(media.id) }
            } message: { media in
                Text(uploads?.preparation(of: media.id) == .unavailable
                    ? MediaUploadMessages.unavailableOffline
                    : MediaUploadMessages.failure(.exportFailed))
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
                if case .failed = media.upload { failedTile = media } else { actionTarget = .existing(media) }
            }
            .accessibilityIdentifier("mediaSection.media")
        case .media(.added(let media)):
            let preparation = uploads?.preparation(of: media.id)
            PickedMediaPreview(media: media)
                .frame(width: Self.tileWidth, height: Self.tileHeight)
                .overlay { PreparationOverlay(preparation: preparation) }
                .clipShape(.rect(cornerRadius: 8))
                .contentShape(.rect)
                .onTapGesture {
                    if preparation == .failed || preparation == .unavailable {
                        failedPick = media
                    } else {
                        actionTarget = .added(media)
                    }
                }
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

extension MediaUploadMessages {
    static let unavailableOffline = "Média indisponible hors connexion"
}

/// Over a finish screen's tile whose export failed before Save (ADR-037 §6): "Échec", or "Média
/// indisponible hors connexion" for an original only in iCloud, picked offline.
private struct PreparationOverlay: View {
    let preparation: MediaUploadBoard.Preparation?

    var body: some View {
        switch preparation {
        case .unavailable:
            label(MediaUploadMessages.unavailableOffline, systemImage: "icloud.slash")
                .accessibilityIdentifier("mediaSection.unavailable")
        case .failed:
            label(MediaUploadMessages.failed, systemImage: "exclamationmark.triangle.fill")
                .accessibilityIdentifier("mediaSection.failed")
        case .exporting, .ready, nil:
            EmptyView()
        }
    }

    private func label(_ text: String, systemImage: String) -> some View {
        ZStack {
            Color.black.opacity(0.55)
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                Text(text).multilineTextAlignment(.center)
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(6)
        }
    }
}
