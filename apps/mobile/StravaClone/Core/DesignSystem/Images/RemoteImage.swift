import SwiftUI

/// Image loaded through the environment's `ImageLoader`, with a placeholder while loading
/// and on failure. A deleted object (`404`) shows the placeholder too; an expired
/// pre-signed URL (`403`) also asks the screen for fresh URLs (`onImageURLExpired`).
/// With `maxPixelSize`, the image is downsampled at decode (`ImageLoader.load`).
struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    var maxPixelSize: CGFloat?
    @ViewBuilder var placeholder: () -> Placeholder

    @Environment(\.imageLoader) private var loader
    @Environment(\.imageURLExpired) private var imageURLExpired
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: Request(url: url, maxPixelSize: maxPixelSize)) {
            guard let url else {
                image = nil
                return
            }
            let result = await loader.load(url, maxPixelSize: maxPixelSize)
            if result == .expired {
                imageURLExpired()
            }
            image = result.image
        }
    }

    private struct Request: Equatable {
        let url: URL?
        let maxPixelSize: CGFloat?
    }
}
