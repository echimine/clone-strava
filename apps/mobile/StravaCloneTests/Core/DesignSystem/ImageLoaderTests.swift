import Foundation
import Testing
import UIKit
@testable import StravaClone

/// Own `URLProtocol` stub, like `APIAthleteStatsRepositoryTests`: suites run in parallel.
private final class ImageURLProtocolStub: URLProtocol, @unchecked Sendable {
    static let status = Locked<Int>(200)
    static let requests = Locked<[URLRequest]>([])
    static let body = Locked<Data>(ImageLoaderTests.png)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.value.append(request)
        let status = Self.status.value
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: status == 200 ? Self.body.value : Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct ImageLoaderTests {
    static let png = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).pngData { context in
        UIColor.orange.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
    }

    /// The same object path signed twice (ADR-037 §1): only the query string differs.
    private let signed = URL(string: "https://bucket.test/avatars/u1/a1.jpg?X-Amz-Signature=aaa&X-Amz-Expires=3600")!
    private let resigned = URL(string: "https://bucket.test/avatars/u1/a1.jpg?X-Amz-Signature=bbb&X-Amz-Expires=3600")!

    /// A 2048 × 1536 photo, like a Media's `original.jpg` (ADR-037 §3).
    static let photo = UIGraphicsImageRenderer(
        size: CGSize(width: 2_048, height: 1_536),
        format: { let format = UIGraphicsImageRendererFormat(); format.scale = 1; return format }()
    ).jpegData(withCompressionQuality: 0.5) { context in
        UIColor.orange.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 2_048, height: 1_536))
    }

    private func makeLoader(status: Int = 200, body: Data = ImageLoaderTests.png, cache: URLCache? = nil) -> ImageLoader {
        ImageURLProtocolStub.status.value = status
        ImageURLProtocolStub.body.value = body
        ImageURLProtocolStub.requests.value = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageURLProtocolStub.self]
        return ImageLoader(
            session: URLSession(configuration: configuration),
            cache: cache ?? URLCache(memoryCapacity: 10_000_000, diskCapacity: 0)
        )
    }

    @Test func twoSignedURLsToTheSamePathDownloadOnce() async throws {
        let loader = makeLoader()

        let first = await loader.load(signed)
        let second = await loader.load(resigned)

        #expect(first.image != nil)
        #expect(second.image != nil)
        #expect(ImageURLProtocolStub.requests.value.count == 1)
    }

    @Test func anExpiredURLAsksTheScreenToReload() async {
        let loader = makeLoader(status: 403)

        #expect(await loader.load(signed) == .expired)
    }

    @Test func aDeletedObjectFallsBackWithoutReloading() async {
        let loader = makeLoader(status: 404)

        #expect(await loader.load(signed) == .missing)
    }

    @Test func theDiskCacheOutlivesTheLoader() async {
        let disk = URLCache(memoryCapacity: 10_000_000, diskCapacity: 0)
        _ = await makeLoader(cache: disk).load(signed)
        let relaunched = ImageLoader(session: .shared, cache: disk)

        #expect(await relaunched.load(resigned).image != nil)
        #expect(ImageURLProtocolStub.requests.value.count == 1)
    }

    @Test func unsignedURLsStillLoadEachPath() async {
        let loader = makeLoader()
        let mapA = URL(string: "https://api.mapbox.com/styles/v1/mapbox/outdoors-v12/static/path-a/auto/360x203@2x?padding=40&access_token=pk")!
        let mapB = URL(string: "https://api.mapbox.com/styles/v1/mapbox/outdoors-v12/static/path-b/auto/360x203@2x?padding=40&access_token=pk")!

        #expect(await loader.load(mapA).image != nil)
        #expect(await loader.load(mapB).image != nil)
        #expect(await loader.load(mapA).image != nil)
        #expect(ImageURLProtocolStub.requests.value.count == 2)
    }

    @Test func aPhotoIsDownsampledAtDecode() async throws {
        let loader = makeLoader(body: Self.photo)

        let image = try #require(await loader.load(signed, maxPixelSize: 1_024).image)

        #expect(pixelSize(of: image) == CGSize(width: 1_024, height: 768))
    }

    @Test func withoutMaxPixelSizeThePhotoKeepsItsSize() async throws {
        let loader = makeLoader(body: Self.photo)

        let image = try #require(await loader.load(signed).image)

        #expect(pixelSize(of: image) == CGSize(width: 2_048, height: 1_536))
    }

    @Test func twoDecodeSizesOfOnePathDownloadOnce() async throws {
        let loader = makeLoader(body: Self.photo)

        let small = try #require(await loader.load(signed, maxPixelSize: 512).image)
        let large = try #require(await loader.load(resigned, maxPixelSize: 1_024).image)

        #expect(pixelSize(of: small).width == 512)
        #expect(pixelSize(of: large).width == 1_024)
        #expect(ImageURLProtocolStub.requests.value.count == 1)
    }

    private func pixelSize(of image: UIImage) -> CGSize {
        CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }
}
