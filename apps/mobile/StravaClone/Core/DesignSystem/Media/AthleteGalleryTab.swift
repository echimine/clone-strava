import SwiftUI

/// French texts of the Galerie tab (ADR-037 §10).
enum GalleryMessages {
    static let tab = "Galerie"
    static let systemImage = "photo.on.rectangle"
    static let empty = "Aucune photo ni vidéo"
    static let errorTitle = "Galerie indisponible"
    static let retry = "Réessayer"
}

/// The profile's Galerie tab (ADR-037 §10), mine or another athlete's: a 3-column grid of
/// squares 2 pt apart, newest first, with infinite scroll. A video carries "▶︎ 0:10" top right.
/// A tap opens the viewer over every loaded Media; its pill opens the Media's Activity.
struct AthleteGalleryTab: View {
    @Bindable var store: AthleteGalleryStore
    let openActivity: @MainActor (ActivityID) -> Void

    private static let spacing: CGFloat = 2
    private let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: 3)

    var body: some View {
        switch store.phase {
        case .idle, .loading where store.items.isEmpty:
            ProgressView().padding(.top, 40)
        case .failed(let message) where store.items.isEmpty:
            ContentUnavailableView {
                Label(GalleryMessages.errorTitle, systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button(GalleryMessages.retry) { Task { await store.refresh() } }
                    .buttonStyle(.borderedProminent)
            }
        default:
            if store.isEmpty {
                ContentUnavailableView(GalleryMessages.empty, systemImage: GalleryMessages.systemImage)
                    .padding(.top, 40)
            } else {
                grid
            }
        }
    }

    private var grid: some View {
        VStack(spacing: Theme.spacing) {
            LazyVGrid(columns: columns, spacing: Self.spacing) {
                ForEach(store.items) { item in
                    Button { store.openMedia(item.media) } label: {
                        GalleryTile(media: item.media)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(ActivityCarouselMessages.label(for: item.media))
                    .accessibilityHint(item.activity.title)
                    .task { await store.loadMoreIfNeeded(current: item) }
                }
            }
            if store.isLoadingMore {
                ProgressView().padding()
            }
        }
        .accessibilityIdentifier("profile.gallery")
        .mediaViewer($store.mediaViewer) { openActivity($0) }
    }
}

/// A square of the grid: the Media's 512 px `thumbUrl` (ADR-037 §7), filled and cropped.
private struct GalleryTile: View {
    let media: ActivityMedia

    var body: some View {
        Color(.secondarySystemBackground)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                RemoteImage(url: media.thumbURL, maxPixelSize: 512) { Color.clear }
            }
            .clipped()
            .overlay(alignment: .topTrailing) {
                if media.kind == .video {
                    HStack(spacing: 3) {
                        Image(systemName: "play.fill")
                        if let duration = media.duration {
                            Text(ActivityMediaSlide.durationLabel(duration)).monospacedDigit()
                        }
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
                    .padding(6)
                    .accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
    }
}
