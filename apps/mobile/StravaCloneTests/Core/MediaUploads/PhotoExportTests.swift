import Foundation
import ImageIO
import Testing
@testable import StravaClone

/// The photo files of ADR-037 §3: `original.jpg` 2048 px at most, `thumb.jpg` 512 px, JPEG,
/// with no EXIF and no GPS.
struct PhotoExportTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("photo-export-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func properties(of url: URL) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(CGImageSourceGetType(source) as String? == "public.jpeg")
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    @Test func aCameraPhotoBecomesA2048PixelJPEGWithoutEXIFOrGPS() throws {
        let camera = MediaUploadHarness.cameraPhoto(width: 4_032, height: 3_024)
        let source = try #require(CGImageSourceCreateWithData(camera as CFData, nil))
        let input = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(input[kCGImagePropertyGPSDictionary] != nil, "the test photo carries GPS")
        let directory = try folder()

        let exported = try PhotoExport.export(camera, into: directory)

        #expect(exported.width == 2_048)
        #expect(exported.height == 1_536)
        #expect(exported.durationMs == nil)
        let original = try properties(of: directory.appendingPathComponent("original.jpg"))
        #expect(original[kCGImagePropertyPixelWidth] as? Int == 2_048)
        #expect(original[kCGImagePropertyPixelHeight] as? Int == 1_536)
        #expect(original[kCGImagePropertyExifDictionary] == nil)
        #expect(original[kCGImagePropertyGPSDictionary] == nil)
        #expect((original[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFModel] == nil)
    }

    @Test func theThumbIs512PixelsWithoutMetadataEither() throws {
        let directory = try folder()

        let exported = try PhotoExport.export(MediaUploadHarness.cameraPhoto(width: 3_024, height: 4_032), into: directory)

        let thumb = try properties(of: directory.appendingPathComponent("thumb.jpg"))
        #expect(thumb[kCGImagePropertyPixelWidth] as? Int == 384)
        #expect(thumb[kCGImagePropertyPixelHeight] as? Int == 512)
        #expect(thumb[kCGImagePropertyGPSDictionary] == nil)
        #expect(thumb[kCGImagePropertyExifDictionary] == nil)
        let sizes = try exported.files.map { file in
            (file.name, file.contentType, try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(file.name).path)[.size] as? Int)
        }
        #expect(sizes.map(\.0) == ["original.jpg", "thumb.jpg"])
        #expect(sizes.allSatisfy { $0.1 == "image/jpeg" })
        #expect(sizes.map(\.2) == exported.files.map(\.byteCount))
    }

    @Test func aSmallPhotoIsNotEnlarged() throws {
        let exported = try PhotoExport.export(MediaUploadHarness.cameraPhoto(width: 800, height: 600), into: folder())

        #expect(exported.width == 800)
        #expect(exported.height == 600)
    }

    @Test func dataThatIsNotAnImageIsRefused() throws {
        #expect(throws: PhotoExport.Failure.unreadable) {
            try PhotoExport.export(Data("not an image".utf8), into: try folder())
        }
    }
}
