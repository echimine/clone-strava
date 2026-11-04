import CoreGraphics
import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import StravaClone

/// The Avatar file the phone sends (ADR-037 §2): a 512×512 JPEG with no EXIF and no GPS,
/// whatever the photo carried.
struct AvatarJPEGTests {
    /// A 1200×800 camera-like JPEG carrying EXIF (date, camera) and a GPS position.
    private func cameraPhoto() throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: 1200, height: 800, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:10:01 08:30:00",
                kCGImagePropertyExifLensModel: "iPhone back camera",
            ],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone"],
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 48.8566, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 2.3522, kCGImagePropertyGPSLongitudeRef: "E",
            ],
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func properties(of jpeg: Data) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    @Test func theTestPhotoReallyCarriesExifAndGPS() throws {
        let original = try properties(of: try cameraPhoto())

        #expect(original[kCGImagePropertyGPSDictionary] != nil)
        #expect(original[kCGImagePropertyExifDictionary] != nil)
    }

    @Test func aCroppedPhotoBecomesA512JPEGWithoutExifNorGPS() throws {
        let photo = try #require(AvatarSourceImage(data: try cameraPhoto()))
        let crop = CGRect(x: 300, y: 100, width: 600, height: 600)

        let jpeg = try #require(AvatarJPEG.encode(photo.image, cropping: crop))

        let output = try properties(of: jpeg)
        #expect(output[kCGImagePropertyPixelWidth] as? Int == 512)
        #expect(output[kCGImagePropertyPixelHeight] as? Int == 512)
        #expect(output[kCGImagePropertyExifDictionary] == nil)
        #expect(output[kCGImagePropertyGPSDictionary] == nil)
        #expect(output[kCGImagePropertyTIFFDictionary] == nil)
        #expect(jpeg.range(of: Data("Exif".utf8)) == nil)
        #expect(jpeg.count <= AvatarJPEG.maxBytes)
    }

    @Test func aPhotoFromTheCameraIsEncodedUpright() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 400), format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return format
        }())
        let portrait = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 400))
        }
        let rotated = try #require(portrait.cgImage.map { UIImage(cgImage: $0, scale: 1, orientation: .right) })

        let photo = try #require(AvatarSourceImage(uiImage: rotated))

        #expect(photo.image.width == 400)
        #expect(photo.image.height == 300)
    }

    @Test func aLargePhotoIsReducedBeforeCropping() throws {
        let context = try #require(CGContext(
            data: nil, width: 5000, height: 4000, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)

        let photo = try #require(AvatarSourceImage(data: data as Data))

        #expect(photo.image.width == AvatarSourceImage.maxPixelSize)
        #expect((1638...1639).contains(photo.image.height))
    }

    @Test func dataThatIsNoImageIsRefused() {
        #expect(AvatarSourceImage(data: Data("pas une image".utf8)) == nil)
    }
}
