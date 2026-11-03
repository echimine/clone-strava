import CoreGraphics
import Foundation
import ImageIO
import UIKit

/// The photo the athlete picked or took, upright and reduced to at most 2048 px on its long
/// side, ready for the crop screen (ADR-037 §2). Only its pixels are kept: the EXIF, the GPS
/// position and the orientation tag of the original file are dropped here.
struct AvatarSourceImage: @unchecked Sendable {
    /// Large enough to zoom into a 512 px crop, small enough for a 48 MP photo not to fill
    /// the memory.
    static let maxPixelSize = 2048

    let image: CGImage

    /// The photo library's file (HEIC, JPEG, PNG…), decoded and turned upright by ImageIO.
    init?(data: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        self.image = image
    }

    /// The camera's picture, drawn upright (its `imageOrientation` applied).
    init?(uiImage: UIImage) {
        let size = uiImage.size
        guard size.width > 0, size.height > 0 else { return nil }
        let pixels = CGSize(width: size.width * uiImage.scale, height: size.height * uiImage.scale)
        let ratio = min(1, CGFloat(Self.maxPixelSize) / max(pixels.width, pixels.height))
        let target = CGSize(width: (pixels.width * ratio).rounded(), height: (pixels.height * ratio).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let drawn = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            uiImage.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let image = drawn.cgImage else { return nil }
        self.image = image
    }

    /// Size in pixels, upright.
    var pixelSize: CGSize { CGSize(width: image.width, height: image.height) }
}
