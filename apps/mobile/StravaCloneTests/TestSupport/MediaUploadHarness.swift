import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import StravaClone

/// Own `URLProtocol` stub for the Media API calls (suites run in parallel): answers each
/// request from a scripted handler, records every request with its body.
final class MediaURLProtocolStub: URLProtocol, @unchecked Sendable {
    static let handler = Locked<(@Sendable (URLRequest) -> (Int, String))?>(nil)
    static let requests = Locked<[URLRequest]>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var recorded = request
        recorded.httpBody = request.httpBody ?? request.httpBodyStream.map(Self.read)
        Self.requests.value.append(recorded)
        let (status, body) = Self.handler.value?(recorded) ?? (500, "")
        if status == 0 {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// The background session's stand-in: records the `PUT`s started and cancelled; the test
/// plays the bucket's answers through `MediaUploadQueue.handle(_:)`.
final class FakeMediaTransfer: MediaFileTransferring, @unchecked Sendable {
    private let state = Locked<(started: [MediaFilePut], cancelled: Set<UUID>, active: Set<MediaFileKey>)>(([], [], []))
    let events: AsyncStream<MediaTransferEvent>
    let continuation: AsyncStream<MediaTransferEvent>.Continuation

    init(active: Set<MediaFileKey> = []) {
        (events, continuation) = AsyncStream.makeStream(of: MediaTransferEvent.self)
        state.value.active = active
    }

    var started: [MediaFilePut] { state.value.started }
    var startedNames: [String] { started.map(\.key.name) }
    var cancelled: Set<UUID> { state.value.cancelled }

    func start(_ put: MediaFilePut) async {
        state.value.started.append(put)
        state.value.active.insert(put.key)
    }

    func cancel(mediaIDs: Set<UUID>) async {
        state.value.cancelled.formUnion(mediaIDs)
        state.value.active = state.value.active.filter { !mediaIDs.contains($0.mediaID) }
    }

    func cancelAll() async {
        state.value.cancelled.formUnion(state.value.active.map(\.mediaID))
        state.value.active = []
    }

    func activeFiles() async -> Set<MediaFileKey> { state.value.active }
}

/// A `MediaUploadQueue` over the real GRDB store in memory, the real API adapter on a stubbed
/// network, a fake background session and real files in a temporary folder.
struct MediaUploadHarness: Sendable {
    static let now = Date(timeIntervalSince1970: 1_792_047_600)

    let database: AppDatabase
    let store: GRDBMediaUploadStore
    let files: MediaUploadFiles
    let analytics = FakeAnalyticsClient()
    let activityID = ActivityID()

    init(database: AppDatabase? = nil, files: MediaUploadFiles? = nil) throws {
        self.database = try database ?? AppDatabase.inMemory()
        store = GRDBMediaUploadStore(database: self.database)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("media-uploads-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.files = files ?? MediaUploadFiles(root: root)
    }

    static func resetNetwork() {
        MediaURLProtocolStub.requests.value = []
        MediaURLProtocolStub.handler.value = nil
    }

    /// "POST upload-urls", "POST media": the API calls sent, in order.
    var requestLines: [String] {
        MediaURLProtocolStub.requests.value.map { request in
            "\(request.httpMethod ?? "") \(request.url!.path.hasSuffix("/upload-urls") ? "upload-urls" : "media")"
        }
    }

    /// The JSON body of the last call to `step` ("upload-urls" or "media").
    func lastBody(_ step: String) throws -> [String: Any]? {
        let request = MediaURLProtocolStub.requests.value.last { request in
            request.url!.path.hasSuffix("/upload-urls") == (step == "upload-urls")
        }
        return try request?.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    @MainActor
    func makeQueue(transfer: FakeMediaTransfer, exporter: MediaExporter = MediaExporter()) -> MediaUploadQueue {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MediaURLProtocolStub.self]
        let authSession = AuthSession(service: "test.media-upload.\(UUID())")
        authSession.clear()
        let apiClient = APIClient(baseURL: URL(string: "https://api.test")!, session: URLSession(configuration: configuration), authSession: authSession)
        return MediaUploadQueue(
            store: store,
            files: files,
            server: APIMediaUploadServer(apiClient: apiClient),
            transfer: transfer,
            sessionRefresher: FakeSessionRefresher(),
            analytics: analytics,
            exporter: exporter,
            now: { Self.now },
            sleep: ManualSleeper().sleep
        )
    }

    // MARK: - Server answers

    /// Routes each API call to `answer(step)`: "upload-urls" or "confirm".
    static func route(_ answer: @escaping @Sendable (String) -> (Int, String)) {
        MediaURLProtocolStub.handler.value = { request in
            answer(request.url!.path.hasSuffix("/upload-urls") ? "upload-urls" : "confirm")
        }
    }

    /// `200` with a `PUT` URL per file of the request, signed `signature`.
    static func uploadURLs(_ signature: String = "first") -> (Int, String) {
        let expiresAt = Self.now.addingTimeInterval(86_400).formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        let files = ["original.jpg", "thumb.jpg"].map { name in
            #"{"name":"\#(name)","uploadUrl":"https://bucket.test/\#(name)?sig=\#(signature)","expiresAt":"\#(expiresAt)"}"#
        }
        return (200, #"{"files":[\#(files.joined(separator: ","))]}"#)
    }

    /// `201` with the confirmed Media of `id`.
    static func confirmed(_ id: UUID) -> (Int, String) {
        let base = "https://bucket.test/test/activities/u/a/media/\(id.uuidString.lowercased())"
        return (201, #"{"media":{"id":"\#(id.uuidString.lowercased())","kind":"photo","width":2048,"height":1536,"durationMs":null,"url":"\#(base)/original.jpg?X-Amz-Expires=3600","posterUrl":null,"thumbUrl":"\#(base)/thumb.jpg?X-Amz-Expires=3600"}}"#)
    }

    static func refused(_ status: Int, _ code: String) -> (Int, String) {
        (status, #"{"error":{"code":"\#(code)","message":"Refused"}}"#)
    }

    // MARK: - Photos

    /// A JPEG straight from a camera: `width` × `height`, with EXIF and GPS.
    static func cameraPhoto(width: Int = 4_032, height: Int = 3_024) -> Data {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:10:15 07:00:00", kCGImagePropertyExifLensModel: "iPhone"],
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 45.764, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 4.8357, kCGImagePropertyGPSLongitudeRef: "E",
            ],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone 17"],
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    static func photo(_ data: Data = cameraPhoto(width: 1_200, height: 900)) -> PickedMedia {
        PickedMedia(source: MediaSource(kind: .photo) { .image(data) })
    }
}
