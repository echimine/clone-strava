import CoreGraphics
import Testing
@testable import StravaClone

/// The crop screen (ADR-037 §2): a circle over the photo, which the athlete drags and pinches;
/// the circle always stays covered by the photo.
struct AvatarCropTests {
    /// A 1200×800 landscape photo under a 300 pt circle: at zoom 1 its height fills the circle.
    private let crop = AvatarCrop(imageSize: CGSize(width: 1200, height: 800), diameter: 300)

    @Test func atFirstTheCircleHoldsTheCentreOfThePhoto() {
        #expect(crop.cropRect == CGRect(x: 200, y: 0, width: 800, height: 800))
        #expect(crop.displayedSize == CGSize(width: 450, height: 300))
    }

    @Test func draggingMovesTheCircleOverThePhoto() {
        let moved = crop.adjusted(zoomBy: 1, movedBy: CGSize(width: 30, height: 0))

        // 30 pt at 0.375 pt per pixel: the photo moves right, the circle sees 80 px further left.
        #expect(moved.cropRect == CGRect(x: 120, y: 0, width: 800, height: 800))
    }

    @Test func draggingStopsAtTheEdgeOfThePhoto() {
        let moved = crop.adjusted(zoomBy: 1, movedBy: CGSize(width: 1_000, height: -1_000))

        #expect(moved.cropRect == CGRect(x: 0, y: 0, width: 800, height: 800))
    }

    @Test func pinchingZoomsIntoTheCentre() {
        let zoomed = crop.adjusted(zoomBy: 2, movedBy: .zero)

        #expect(zoomed.cropRect == CGRect(x: 400, y: 200, width: 400, height: 400))
    }

    @Test func theZoomStaysBetweenTheWholeHeightAndFourTimes() {
        #expect(crop.adjusted(zoomBy: 0.2, movedBy: .zero).zoom == 1)
        #expect(crop.adjusted(zoomBy: 10, movedBy: .zero).zoom == 4)
    }

    @Test func zoomingOutPullsAMovedPhotoBackOverTheCircle() {
        let zoomedAndMoved = crop.adjusted(zoomBy: 3, movedBy: CGSize(width: 0, height: 300))

        let zoomedOut = zoomedAndMoved.adjusted(zoomBy: 1 / 3, movedBy: .zero)

        #expect(zoomedOut.cropRect == CGRect(x: 200, y: 0, width: 800, height: 800))
    }
}
