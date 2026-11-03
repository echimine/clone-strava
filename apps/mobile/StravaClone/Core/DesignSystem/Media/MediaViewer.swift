import AVKit
import SwiftUI

/// The full-screen viewer (ADR-037 §10), variant A of the prototype: black, one Media at a time
/// in full (aspect fit), a horizontal swipe through the list; × on the left and "3 sur 8" over
/// the Activity's date in the middle; a swipe down closes. A video plays with sound and the
/// native controls while on screen. The map is never in it. From the Gallery, no "n sur N"
/// and a "titre · Voir l'activité ›" pill at the bottom.
struct MediaViewer: View {
    /// "Voir l'activité" from the Gallery: called once the viewer is closed.
    var openActivity: ((ActivityID) -> Void)?

    @State private var model: MediaViewerModel
    @State private var drag: CGFloat = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.imageURLExpired) private var imageURLExpired

    init(request: MediaViewerRequest, playback: VideoPlayback, openActivity: ((ActivityID) -> Void)? = nil) {
        _model = State(initialValue: MediaViewerModel(request: request, playback: playback))
        self.openActivity = openActivity
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(1 - min(drag / 400, 0.6))
                .ignoresSafeArea()
            pager
                .offset(y: drag)
                .simultaneousGesture(swipeDownToClose)
        }
        .overlay(alignment: .top) { topBar.opacity(drag == 0 ? 1 : 0) }
        .overlay(alignment: .bottom) { activityPill.opacity(drag == 0 ? 1 : 0) }
        .environment(\.colorScheme, .dark)
        .presentationBackground(.clear)
        .statusBarHidden()
        .onAppear {
            // A video's expired URL reloads the screen under the viewer, as an image does.
            let imageURLExpired = imageURLExpired
            model.onVideoURLExpired = { imageURLExpired() }
            model.appear()
        }
        .onDisappear { model.disappear() }
        .accessibilityIdentifier("mediaViewer")
    }

    private var pager: some View {
        TabView(selection: Binding(get: { model.index }, set: { model.show($0) })) {
            ForEach(Array(model.request.items.enumerated()), id: \.element.id) { offset, item in
                MediaViewerPage(media: item.media, player: model.player(for: item.media))
                    // Centred on the screen, not between the safe area's insets.
                    .ignoresSafeArea()
                    .tag(offset)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
    }

    /// A mostly vertical drag down moves the Media; past 140 pt it closes, else it springs back.
    private var swipeDownToClose: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard let offset = MediaViewerSwipe.offset(for: value.translation) else { return }
                drag = offset
            }
            .onEnded { _ in
                if MediaViewerSwipe.closes(at: drag) {
                    dismiss()
                } else {
                    withAnimation(.snappy) { drag = 0 }
                }
            }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .foregroundStyle(.white)
            .accessibilityLabel(MediaViewerMessages.close)
            .accessibilityIdentifier("mediaViewer.close")
            Spacer()
            VStack(spacing: 2) {
                if let position = model.position {
                    Text(position)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .accessibilityIdentifier("mediaViewer.position")
                }
                Text(ActivityFormatters.dateTime(model.current.activity.startedAt))
                    .font(.caption)
            }
            .foregroundStyle(.white)
            .accessibilityElement(children: .combine)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 8)
        .background(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    /// The Gallery's link to the Media's Activity (ADR-037 §10).
    @ViewBuilder private var activityPill: some View {
        if model.request.mode == .gallery, let openActivity {
            let activity = model.current.activity
            Button {
                dismiss()
                openActivity(activity.id)
            } label: {
                HStack(spacing: 6) {
                    Text(activity.title)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Text("·").foregroundStyle(.secondary)
                    Text(MediaViewerMessages.openActivity)
                    Image(systemName: "chevron.right").font(.caption.weight(.bold))
                }
                .font(.subheadline)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.spacing)
            .padding(.bottom, 24)
            .accessibilityIdentifier("mediaViewer.openActivity")
        }
    }
}

/// The viewer's swipe to close (ADR-037 §10): down only, an upward drag leaves the Media in place.
enum MediaViewerSwipe {
    static let closingDistance: CGFloat = 140

    /// How far the Media follows a drag; nil for a mostly horizontal one (the pager's).
    static func offset(for translation: CGSize) -> CGFloat? {
        guard abs(translation.height) > abs(translation.width) else { return nil }
        return max(0, translation.height)
    }

    static func closes(at offset: CGFloat) -> Bool {
        offset > closingDistance
    }
}

/// One Media in full, aspect fit. A photo shows `url`; a video shows its poster until its
/// player exists, then the player with the native controls.
private struct MediaViewerPage: View {
    let media: ActivityMedia
    let player: AVPlayer?

    var body: some View {
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                RemoteImage(url: media.stillURL) {
                    ProgressView().tint(.white)
                }
            }
            .overlay {
                if media.kind == .video, let player {
                    VideoPlayer(player: player)
                }
            }
            .clipped()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(ActivityCarouselMessages.label(for: media))
    }

    private var aspectRatio: CGFloat {
        guard media.width > 0, media.height > 0 else { return 1 }
        return CGFloat(media.width) / CGFloat(media.height)
    }
}

extension View {
    /// Shows the full-screen viewer while `request` is set (ADR-037 §10). It takes the app's
    /// single video playback, so the carousel under it stops its muted loop.
    /// - Parameter openActivity: the Gallery's "Voir l'activité" (ignored from a carousel).
    func mediaViewer(_ request: Binding<MediaViewerRequest?>, openActivity: ((ActivityID) -> Void)? = nil) -> some View {
        modifier(MediaViewerPresenter(request: request, openActivity: openActivity))
    }
}

private struct MediaViewerPresenter: ViewModifier {
    @Binding var request: MediaViewerRequest?
    let openActivity: ((ActivityID) -> Void)?
    @Environment(\.videoPlayback) private var playback
    @Environment(\.imageURLExpired) private var imageURLExpired

    func body(content: Content) -> some View {
        content.fullScreenCover(item: $request) { request in
            MediaViewer(request: request, playback: playback, openActivity: openActivity)
                .environment(\.imageURLExpired, imageURLExpired)
        }
    }
}
