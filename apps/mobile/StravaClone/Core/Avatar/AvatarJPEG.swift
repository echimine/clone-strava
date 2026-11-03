import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The Avatar file (ADR-037 §2): a 512×512 JPEG, quality ~0.8, written by ImageIO, with no
/// EXIF and no GPS. Under the API's 1 MB limit (`AVATAR_MAX_BYTES`).
enum AvatarJPEG {
    static let side = 512
    static let maxBytes = 1_048_576
    /// Lower qualities are tried only if a busy photo would exceed `maxBytes`.
    private static let qualities: [CGFloat] = [0.8, 0.6, 0.4]

    /// `crop` is in the pixels of `image`, as the crop screen computed it.
    static func encode(_ image: CGImage, cropping crop: CGRect) -> Data? {
        guard let square = render(image, cropping: crop) else { return nil }
        for quality in qualities {
            guard let jpeg = write(square, quality: quality) else { return nil }
            if jpeg.count <= maxBytes { return jpeg }
        }
        return nil
    }

    private static func render(_ image: CGImage, cropping crop: CGRect) -> CGImage? {
        guard
            let cropped = image.cropping(to: crop.integral),
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        else { return nil }
        context.interpolationQuality = .high
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: side, height: side))
        return context.makeImage()
    }

    private static func write(_ image: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImageMetadataShouldExcludeGPS: true,
        ]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return withoutMetadataSegments(data as Data)
    }

    /// ImageIO always writes a small EXIF block (colour space, dimensions): the APP1 (EXIF,
    /// XMP) and APP13 (IPTC) segments are cut out of the header. The ICC profile (APP2) and
    /// the image data are kept as written.
    static func withoutMetadataSegments(_ jpeg: Data) -> Data {
        let bytes = [UInt8](jpeg)
        guard bytes.count > 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return jpeg }
        var output: [UInt8] = [0xFF, 0xD8]
        var index = 2
        while index + 4 <= bytes.count, bytes[index] == 0xFF {
            let marker = bytes[index + 1]
            // Start of scan: the rest is image data.
            if marker == 0xDA { break }
            let length = Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])
            let end = index + 2 + length
            guard length >= 2, end <= bytes.count else { return jpeg }
            if marker != 0xE1 && marker != 0xED {
                output.append(contentsOf: bytes[index..<end])
            }
            index = end
        }
        output.append(contentsOf: bytes[index...])
        return Data(output)
    }
}
