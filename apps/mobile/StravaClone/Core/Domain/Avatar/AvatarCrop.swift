import CoreGraphics

/// Geometry of the crop screen (ADR-037 §2): the photo under a circle of `diameter` points,
/// zoomed and moved by the athlete. At zoom 1 the photo's short side fills the circle; the
/// circle never shows anything but the photo.
struct AvatarCrop: Equatable, Sendable {
    static let maxZoom: CGFloat = 4

    /// The photo, in pixels.
    let imageSize: CGSize
    /// The circle, in points.
    let diameter: CGFloat
    /// 1 to `maxZoom`.
    private(set) var zoom: CGFloat = 1
    /// Where the photo's centre sits from the circle's centre, in points.
    private(set) var offset: CGSize = .zero

    init(imageSize: CGSize, diameter: CGFloat) {
        self.imageSize = imageSize
        self.diameter = diameter
    }

    /// Points per pixel of the photo on screen.
    var scale: CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        return diameter / min(imageSize.width, imageSize.height) * zoom
    }

    /// The photo's size on screen.
    var displayedSize: CGSize {
        CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    /// What the circle holds, in the photo's pixels (origin top left): the square to encode.
    var cropRect: CGRect {
        let side = min(imageSize.width, imageSize.height) / zoom
        let centerX = imageSize.width / 2 - offset.width / scale
        let centerY = imageSize.height / 2 - offset.height / scale
        return CGRect(x: centerX - side / 2, y: centerY - side / 2, width: side, height: side)
    }

    /// This crop after a pinch (`zoomBy`, relative) and a drag (`movedBy`, in points), kept
    /// within the zoom range and with the circle covered. The point under the circle's centre
    /// stays there while zooming.
    func adjusted(zoomBy magnification: CGFloat, movedBy translation: CGSize) -> AvatarCrop {
        var next = self
        next.zoom = min(max(zoom * magnification, 1), Self.maxZoom)
        let ratio = next.zoom / zoom
        let size = next.displayedSize
        let maxX = max(0, (size.width - diameter) / 2)
        let maxY = max(0, (size.height - diameter) / 2)
        next.offset = CGSize(
            width: min(max(offset.width * ratio + translation.width, -maxX), maxX),
            height: min(max(offset.height * ratio + translation.height, -maxY), maxY)
        )
        return next
    }
}
