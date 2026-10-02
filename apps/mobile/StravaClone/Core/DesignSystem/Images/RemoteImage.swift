import SwiftUI

/// Image loaded through the environment's `ImageLoader`, with a placeholder while loading
/// and on failure.
struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var placeholder: () -> Placeholder

    @Environment(\.imageLoader) private var loader
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
            image = await loader.image(for: url)
        }
    }
}
