import ImageIO
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
    private var inFlight: [URL: Task<Result<Data, DownloadFailure>, Never>] = [:]

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
    /// tries the network again. With `maxPixelSize`, the image is downsampled at decode so its
    /// longest side is at most that many pixels (a 2048 px Media photo in a 250 pt carousel,
    /// ADR-037 §7); the file is downloaded and stored on disk once for every size.
    func load(_ url: URL, maxPixelSize: CGFloat? = nil) async -> ImageLoadResult {
        let key = Self.cacheKey(for: url)
        let memoryKey = Self.memoryKey(key, maxPixelSize: maxPixelSize)
        if let cached = memory.object(forKey: memoryKey as NSURL) {
            return .loaded(cached)
        }
        let result: ImageLoadResult
        if let stored = cache.cachedResponse(for: URLRequest(url: key)) {
            result = Self.decode(stored.data, maxPixelSize: maxPixelSize).map(ImageLoadResult.loaded) ?? .failed
        } else {
            switch await download(url, key: key) {
            case .success(let data):
                result = Self.decode(data, maxPixelSize: maxPixelSize).map(ImageLoadResult.loaded) ?? .failed
            case .failure(let failure):
                result = failure.result
            }
        }
        if case let .loaded(image) = result {
            memory.setObject(image, forKey: memoryKey as NSURL)
        }
        return result
    }

    /// The file of `url`, downloaded once for concurrent calls and stored on disk under `key`.
    private func download(_ url: URL, key: URL) async -> Result<Data, DownloadFailure> {
        if let task = inFlight[key] {
            return await task.value
        }
        let session = session
        let cache = cache
        let task = Task<Result<Data, DownloadFailure>, Never> {
            guard
                let (data, response) = try? await session.data(from: url),
                let http = response as? HTTPURLResponse
            else { return .failure(DownloadFailure(result: .failed)) }
            switch http.statusCode {
            case 200..<300:
                guard UIImage(data: data) != nil else { return .failure(DownloadFailure(result: .failed)) }
                cache.storeCachedResponse(CachedURLResponse(response: response, data: data), for: URLRequest(url: key))
                return .success(data)
            case 403:
                return .failure(DownloadFailure(result: .expired))
            case 404:
                return .failure(DownloadFailure(result: .missing))
            default:
                return .failure(DownloadFailure(result: .failed))
            }
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }

    /// One memory entry per path and decode size.
    private static func memoryKey(_ key: URL, maxPixelSize: CGFloat?) -> URL {
        guard let maxPixelSize else { return key }
        return URL(string: "\(key.absoluteString)#\(Int(maxPixelSize.rounded(.up)))") ?? key
    }

    /// The full image, or a thumbnail decoded straight at `maxPixelSize` (ImageIO), never the
    /// full bitmap first.
    private static func decode(_ data: Data, maxPixelSize: CGFloat?) -> UIImage? {
        guard let maxPixelSize else { return UIImage(data: data) }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize.rounded(.up)),
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
        return UIImage(cgImage: image)
    }
}

/// Why a download gave no image: the `ImageLoadResult` to return.
private struct DownloadFailure: Error {
    let result: ImageLoadResult
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
