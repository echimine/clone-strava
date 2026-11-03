import AVFoundation
import CoreTransferable
import ImageIO
import PhotosUI
import SwiftUI

extension MediaUploadMessages {
    static let videoTrimmed = "Vidéo coupée à 1 min"
}

extension PickedMedia {
    /// A photo or a video of the library, by what the item holds (a Live Photo is a photo: its
    /// key still).
    init(item: PhotosPickerItem) {
        let types = item.supportedContentTypes
        if !types.contains(where: { $0.conforms(to: .image) }), types.contains(where: { $0.conforms(to: .movie) }) {
            self.init(video: item)
        } else {
            self.init(photo: item)
        }
    }

    /// A photo of the library, read only when exported (a Live Photo gives its key still).
    init(photo item: PhotosPickerItem) {
        self.init(source: MediaSource(kind: .photo) {
            guard let data = try await item.loadTransferable(type: Data.self) else { throw MediaExporter.Failure.failed }
            return .image(data)
        })
    }

    /// A video of the library, copied out of Photos at the first read (its tile or its export).
    init(video item: PhotosPickerItem) {
        self.init(source: .video(PickedMovie {
            guard let movie = try await item.loadTransferable(type: LibraryMovie.self) else { throw MediaExporter.Failure.failed }
            return movie.url
        }))
    }
}

/// A library video received as a file: Photos deletes its own file once the import returns, so
/// it is copied under `PickedMovie.root` (the `PickedMovie` deletes it).
struct LibraryMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let copy = try PickedMovie.destination(extension: received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return LibraryMovie(url: copy)
        }
    }
}

/// A Media picked before "Enregistrer", decoded small from the library original: a photo, or
/// a video's first frame with its duration (cut to 1:00) and "Vidéo coupée à 1 min".
struct PickedMediaPreview: View {
    let media: PickedMedia

    private struct Preview {
        var image: UIImage?
        var duration: Duration?
        var trimmed = false
    }

    @State private var preview = Preview()

    var body: some View {
        Color(.tertiarySystemFill)
            .overlay {
                if let image = preview.image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .overlay(alignment: .topTrailing) {
                if let duration = preview.duration {
                    VideoDurationBadge(duration: duration)
                }
            }
            .overlay(alignment: .bottom) {
                if preview.trimmed {
                    Text(MediaUploadMessages.videoTrimmed)
                        .font(.caption2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 3)
                        .frame(maxWidth: .infinity)
                        .background(.black.opacity(0.6))
                        .accessibilityIdentifier("mediaSection.videoTrimmed")
                }
            }
            .clipped()
            .task(id: media.id) {
                preview = await Self.preview(of: media.source)
            }
    }

    private static func preview(of source: MediaSource) async -> Preview {
        if let movie = source.movie {
            guard let file = try? await movie.file(), let duration = try? await movie.duration() else { return Preview() }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: file))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 256, height: 256)
            let image = try? await generator.image(at: .zero).image
            return Preview(
                image: image.map(UIImage.init(cgImage:)),
                duration: min(duration, VideoExport.maxDuration),
                trimmed: VideoExport.isTrimmed(duration)
            )
        }
        guard case .image(let data)? = try? await source.load(),
              let imageSource = CGImageSourceCreateWithData(data as CFData, nil)
        else { return Preview() }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 256,
        ] as CFDictionary
        return Preview(image: CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options).map(UIImage.init(cgImage:)))
    }
}

/// "0:42" over a video tile of the strip.
struct VideoDurationBadge: View {
    let duration: Duration

    var body: some View {
        Text(ActivityMediaSlide.durationLabel(duration))
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.black.opacity(0.55), in: Capsule())
            .foregroundStyle(.white)
            .padding(4)
            .accessibilityHidden(true)
    }
}
