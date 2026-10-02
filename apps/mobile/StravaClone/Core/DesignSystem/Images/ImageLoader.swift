import SwiftUI
import UIKit

/// Downloads and caches remote images (avatars, static maps, ADR-029): decoded images in
/// memory, responses in a disk `URLCache`. Static map URLs are deterministic, so the HTTP
/// cache serves them again across launches. Concurrent requests for one URL share a task.
actor ImageLoader {
    private let session: URLSession
    private let memory = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.urlCache = URLCache(memoryCapacity: 20_000_000, diskCapacity: 200_000_000)
            configuration.requestCachePolicy = .returnCacheDataElseLoad
            self.session = URLSession(configuration: configuration)
        }
        memory.countLimit = 200
    }

    /// `nil` when the image cannot be downloaded or decoded.
    func image(for url: URL) async -> UIImage? {
        if let cached = memory.object(forKey: url as NSURL) {
            return cached
        }
        if let task = inFlight[url] {
            return await task.value
        }
        let session = session
        let task = Task<UIImage?, Never> {
            guard
                let result = try? await session.data(from: url),
                let http = result.1 as? HTTPURLResponse,
                (200..<300).contains(http.statusCode)
            else { return nil }
            return UIImage(data: result.0)
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image {
            memory.setObject(image, forKey: url as NSURL)
        }
        return image
    }
}

extension EnvironmentValues {
    /// Shared loader, injected by the app root (`Di`).
    @Entry var imageLoader = ImageLoader()
    /// Public Mapbox token used by static map images (ADR-029).
    @Entry var mapboxAccessToken = ""
}
