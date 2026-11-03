import SwiftUI

/// One Media in the carousel (ADR-037 §7, §10), filling its slide. A photo shows `url`,
/// downsampled at decode to the size it fills. A video shows `posterURL`, its duration top
/// right and, while it is the current slide, plays muted and looped over the poster with a
/// sound button bottom right. Only one video plays in the app at a time (`VideoPlayback`).
struct ActivityMediaSlide: View {
    let media: ActivityMedia
    /// The slide is the carousel's current one: a video may play.
    var isCurrent = false

    @Environment(\.videoPlayback) private var playback
    @Environment(\.displayScale) private var displayScale
    /// This slide on this screen: the same Media can be shown by two carousels at once.
    @State private var playbackID = UUID()
    @State private var isShown = false
    @State private var muted = true

    var body: some View {
        let plays = playback.playing == playbackID
        Color.clear
            .overlay {
                GeometryReader { proxy in
                    RemoteImage(url: imageURL(for: proxy.size), maxPixelSize: maxPixelSize(for: proxy.size)) {
                        Color(.tertiarySystemFill)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
            .overlay {
                if plays {
                    LoopingVideoPlayer(url: media.url, muted: muted)
                        .allowsHitTesting(false)
                }
            }
            .clipped()
            .overlay {
                if let upload = media.upload {
                    MediaUploadOverlay(mediaID: media.id, status: upload)
                }
            }
            .overlay {
                if media.kind == .video, !plays, media.upload == nil {
                    Image(systemName: "play.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(.black.opacity(0.45), in: Circle())
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let duration = media.duration, media.kind == .video {
                    Text(Self.durationLabel(duration))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.55), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(8)
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if plays {
                    Button {
                        muted.toggle()
                    } label: {
                        Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.footnote)
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(.black.opacity(0.45), in: Circle())
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(2)
                    .accessibilityLabel(muted ? ActivityCarouselMessages.soundOn : ActivityCarouselMessages.soundOff)
                    .accessibilityIdentifier("activityCarousel.sound")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(ActivityCarouselMessages.label(for: media))
            .onAppear {
                isShown = true
                updateClaim()
            }
            .onDisappear {
                isShown = false
                updateClaim()
            }
            .onChange(of: isCurrent) { updateClaim() }
            .onChange(of: plays) {
                // Back to muted for the next time this video plays.
                if !plays { muted = true }
            }
    }

    private func updateClaim() {
        if media.kind == .video, media.upload == nil, isShown, isCurrent {
            playback.claim(playbackID)
        } else {
            playback.release(playbackID)
        }
    }

    /// Nil until the slide has a size, so the photo is never decoded at full size, and while a
    /// local Media is exported (no file yet).
    private func imageURL(for size: CGSize) -> URL? {
        guard size.width > 0, size.height > 0, media.upload != .exporting else { return nil }
        return media.kind == .video ? media.posterURL : media.url
    }

    private func maxPixelSize(for size: CGSize) -> CGFloat? {
        guard size.width > 0, size.height > 0 else { return nil }
        return Self.decodePixelSize(width: media.width, height: media.height, filling: size, scale: displayScale)
    }

    /// The longest side, in pixels, a `width` × `height` image needs to fill `size` points at
    /// `scale` (aspect fill), rounded up to a multiple of 128 so small layout changes reuse the
    /// decoded image, and never more than the image itself.
    nonisolated static func decodePixelSize(width: Int, height: Int, filling size: CGSize, scale: CGFloat) -> CGFloat {
        let longest = CGFloat(max(width, height, 1))
        guard width > 0, height > 0 else { return longest }
        let fill = max(size.width * scale / CGFloat(width), size.height * scale / CGFloat(height))
        let needed = (longest * fill / 128).rounded(.up) * 128
        return min(needed, longest)
    }

    /// "0:10", "1:05", "1:02:03".
    nonisolated static func durationLabel(_ duration: Duration) -> String {
        let total = Int(duration.components.seconds)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
        }
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}
