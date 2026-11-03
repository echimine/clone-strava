import SwiftUI

/// Image loaded through the environment's `ImageLoader`, with a placeholder while loading
/// and on failure. A deleted object (`404`) shows the placeholder too; an expired
/// pre-signed URL (`403`) also asks the screen for fresh URLs (`onImageURLExpired`).
struct RemoteImage<Placeholder: View>: View {
    let url: URL?
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
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            let result = await loader.load(url)
            if result == .expired {
                imageURLExpired()
            }
            image = result.image
        }
    }
}
