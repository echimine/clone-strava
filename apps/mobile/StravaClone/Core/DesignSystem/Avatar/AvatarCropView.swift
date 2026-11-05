import SwiftUI

/// The crop screen (ADR-037 §2), as Strava's: the photo on black under a circle, moved with
/// a drag and zoomed with a pinch; outside the circle is dimmed. "Choisir" hands back the
/// square the circle holds, in the photo's pixels.
struct AvatarCropView: View {
    let photo: AvatarSourceImage
    let choose: (CGRect) -> Void
    let cancel: () -> Void

    @State private var crop: AvatarCrop?
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag: CGSize = .zero

    private static let margin: CGFloat = 16

    var body: some View {
        GeometryReader { geometry in
            let diameter = max(1, min(geometry.size.width, geometry.size.height) - 2 * Self.margin)
            let committed = crop ?? AvatarCrop(imageSize: photo.pixelSize, diameter: diameter)
            let shown = committed.adjusted(zoomBy: pinch, movedBy: drag)
            ZStack {
                Image(decorative: photo.image, scale: 1)
                    .resizable()
                    .frame(width: shown.displayedSize.width, height: shown.displayedSize.height)
                    .offset(shown.offset)
                CircleCutout(diameter: diameter)
                    .fill(.black.opacity(0.6), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)
                Circle()
                    .strokeBorder(.white.opacity(0.8), lineWidth: 1)
                    .frame(width: diameter, height: diameter)
                    .allowsHitTesting(false)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(.rect)
            .gesture(gesture(from: committed))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AvatarMessages.cropPhoto)
            .accessibilityHint(AvatarMessages.cropZoomHint)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: crop = committed.adjusted(zoomBy: 1.15, movedBy: .zero)
                case .decrement: crop = committed.adjusted(zoomBy: 1 / 1.15, movedBy: .zero)
                @unknown default: break
                }
            }
            .onAppear { crop = crop ?? committed }
        }
        .clipped()
        .background(.black)
        .overlay(alignment: .top) {
            Text(AvatarMessages.cropTitle)
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.top, Self.margin)
                .accessibilityAddTraits(.isHeader)
        }
        .overlay(alignment: .bottom) { buttons }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("avatar.crop")
    }

    private var buttons: some View {
        HStack {
            Button(AvatarMessages.cancel, action: cancel)
                .accessibilityIdentifier("avatar.crop.cancel")
            Spacer()
            Button(AvatarMessages.choose) {
                if let crop { choose(crop.cropRect) }
            }
            .fontWeight(.semibold)
            .accessibilityIdentifier("avatar.crop.choose")
        }
        .font(.body)
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private func gesture(from committed: AvatarCrop) -> some Gesture {
        SimultaneousGesture(
            MagnifyGesture().updating($pinch) { value, state, _ in state = value.magnification },
            DragGesture(minimumDistance: 0).updating($drag) { value, state, _ in state = value.translation }
        )
        .onEnded { value in
            crop = committed.adjusted(
                zoomBy: value.first?.magnification ?? 1,
                movedBy: value.second?.translation ?? .zero
            )
        }
    }
}

/// The whole screen with a round hole in the middle (even-odd fill).
private struct CircleCutout: Shape {
    let diameter: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addEllipse(in: CGRect(
            x: rect.midX - diameter / 2,
            y: rect.midY - diameter / 2,
            width: diameter,
            height: diameter
        ))
        return path
    }
}
