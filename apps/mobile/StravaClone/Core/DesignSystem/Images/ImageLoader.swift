import SwiftUI
import UIKit

/// Downloads and caches remote images (avatars, static maps, Media): decoded images in
/// memory, responses on disk. Everything is cached by the URL **without its query string**
/// (ADR-037 §1): a pre-signed URL changes in every API response, but the object path does
/// not, and the content of a path never changes, so an entry leaves the cache only at the
/// cache's size limit. Concurrent requests for one path share a task.
actor ImageLoader {
    /// App-wide instance: one memory and disk cache for every screen.
    static let shared = ImageLoader()

    private let session: URLSession
    private let cache: URLCache
    private let memory = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<ImageLoadResult, Never>] = [:]

    /// The disk cache is filled by hand under the path key, so `session` must not cache.
    init(session: URLSession? = nil, cache: URLCache? = nil) {
        self.cache = cache ?? URLCache(memoryCapacity: 20_000_000, diskCapacity: 200_000_000)
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: configuration)
        }
        memory.countLimit = 200
    }

    /// The object path: `url` without its query string and fragment.
    static func cacheKey(for url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.query = nil
        components.fragment = nil
        return components.url ?? url
    }

    /// Cached image, else downloaded one. A failed load is not remembered: the next call
    /// tries the network again.
    func load(_ url: URL) async -> ImageLoadResult {
        let key = Self.cacheKey(for: url)
        if let cached = memory.object(forKey: key as NSURL) {
            return .loaded(cached)
        }
        let keyRequest = URLRequest(url: key)
        if let stored = cache.cachedResponse(for: keyRequest), let image = UIImage(data: stored.data) {
            memory.setObject(image, forKey: key as NSURL)
            return .loaded(image)
        }
        if let task = inFlight[key] {
            return await task.value
        }
        let session = session
        let cache = cache
        let task = Task<ImageLoadResult, Never> {
            guard
                let (data, response) = try? await session.data(from: url),
                let http = response as? HTTPURLResponse
            else { return .failed }
            switch http.statusCode {
            case 200..<300:
                guard let image = UIImage(data: data) else { return .failed }
                cache.storeCachedResponse(CachedURLResponse(response: response, data: data), for: keyRequest)
                return .loaded(image)
            case 403:
                return .expired
            case 404:
                return .missing
            default:
                return .failed
            }
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if case let .loaded(image) = result {
            memory.setObject(image, forKey: key as NSURL)
        }
        return result
    }
}

/// Outcome of `ImageLoader.load(_:)`.
enum ImageLoadResult: Equatable {
    case loaded(UIImage)
    /// `403`: the pre-signed URL expired. The screen must reload to get fresh URLs.
    case expired
    /// `404`: the object was deleted (a replaced Avatar, a removed Media). The view shows its
    /// placeholder (the initials for `AvatarView`); reloading would not bring it back.
    case missing
    /// Network error, other status, or undecodable data: the view shows its placeholder.
    case failed
}

extension EnvironmentValues {
    /// Shared loader, injected by the app root (`Di`).
    @Entry var imageLoader: ImageLoader = .shared
    /// Public Mapbox token used by static map images (ADR-029).
    @Entry var mapboxAccessToken = ""
}

extension ImageLoadResult {
    /// The image when loaded, else `nil`.
    var image: UIImage? {
        if case let .loaded(image) = self { image } else { nil }
    }
}
