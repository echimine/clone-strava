import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A photo's files (ADR-037 §3), made by ImageIO: `original.jpg`, 2048 px at most, and
/// `thumb.jpg`, 512 px, both JPEG at quality 0.8. Any format ImageIO reads goes in (HEIC is
/// converted); the orientation is applied to the pixels. Only the pixels are written: no EXIF,
/// no GPS, no TIFF or maker data.
enum PhotoExport {
    static let originalMaxPixelSize = 2_048
    static let thumbMaxPixelSize = 512
    static let quality = 0.8
    /// The API's limits (`MEDIA_FILE_SPECS`): a larger file would be refused.
    static let originalMaxBytes = 8 * 1_048_576
    static let thumbMaxBytes = 1_048_576

    enum Failure: Error, Equatable {
        case unreadable
        case encoding
        case tooLarge
    }

    /// Writes both files into `directory`; returns the original's size in pixels and the files.
    static func export(_ data: Data, into directory: URL) throws(Failure) -> ExportedMedia {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0
        else { throw .unreadable }
        let original = try downsampled(source, maxPixelSize: originalMaxPixelSize)
        let thumb = try downsampled(source, maxPixelSize: thumbMaxPixelSize)
        let originalData = try jpeg(original)
        let thumbData = try jpeg(thumb)
        guard originalData.count <= originalMaxBytes, thumbData.count <= thumbMaxBytes else { throw .tooLarge }
        do {
            try originalData.write(to: directory.appendingPathComponent(MediaUploadFile.originalPhoto))
            try thumbData.write(to: directory.appendingPathComponent(MediaUploadFile.thumb))
        } catch {
            throw .encoding
        }
        return ExportedMedia(
            width: original.width,
            height: original.height,
            durationMs: nil,
            files: [
                MediaUploadFile(name: MediaUploadFile.originalPhoto, contentType: "image/jpeg", byteCount: originalData.count),
                MediaUploadFile(name: MediaUploadFile.thumb, contentType: "image/jpeg", byteCount: thumbData.count),
            ]
        )
    }

    /// The image with its orientation applied, its longest side at most `maxPixelSize` (never
    /// upscaled), decoded straight at that size.
    private static func downsampled(_ source: CGImageSource, maxPixelSize: Int) throws(Failure) -> CGImage {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { throw .unreadable }
        return image
    }

    /// The pixels alone: no properties are copied from the source.
    static func jpeg(_ image: CGImage) throws(Failure) -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw .encoding
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination),
              let stripped = strippingMetadata(data as Data)
        else { throw .encoding }
        return stripped
    }

    /// The JPEG without its APP1 (EXIF, XMP), APP13 (IPTC) and comment segments: ImageIO always
    /// writes a small EXIF block (the pixel dimensions) even when given no property. The colour
    /// profile (APP2) stays, so a Display P3 photo keeps its colours. Nil if `jpeg` is not one.
    static func strippingMetadata(_ jpeg: Data) -> Data? {
        let bytes = [UInt8](jpeg)
        guard bytes.count > 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return nil }
        var output: [UInt8] = [0xFF, 0xD8]
        var index = 2
        while index + 4 <= bytes.count {
            guard bytes[index] == 0xFF else { return nil }
            let marker = bytes[index + 1]
            // Start of scan: the compressed image follows, up to the end.
            if marker == 0xDA {
                output.append(contentsOf: bytes[index...])
                return Data(output)
            }
            let length = Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])
            let end = index + 2 + length
            guard length >= 2, end <= bytes.count else { return nil }
            if marker != 0xE1, marker != 0xED, marker != 0xFE {
                output.append(contentsOf: bytes[index ..< end])
            }
            index = end
        }
        return nil
    }
}

/// Turns a picked Media into its files (ADR-037 §3). Photos only for now; the video branch
/// (MP4 720p, poster, thumb, 1 min at most) comes with #183.
struct MediaExporter: Sendable {
    enum Failure: Error, Equatable {
        case unsupported
        case failed
    }

    var exportPhoto: @Sendable (Data, URL) throws -> ExportedMedia = { data, directory in
        try PhotoExport.export(data, into: directory)
    }

    func export(_ source: MediaSource, into directory: URL) async throws -> ExportedMedia {
        switch try await source.load() {
        case .image(let data):
            return try exportPhoto(data, directory)
        case .movie:
            throw Failure.unsupported
        }
    }
}
