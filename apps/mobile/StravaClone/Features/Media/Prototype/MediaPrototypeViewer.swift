#if DEBUG
import AVKit
import SwiftUI

// PROTOTYPE — throwaway (see MediaPrototype.swift).
// Le visionneur plein écran, ouvert depuis un carrousel ou la Galerie. Trois variantes :
//   A « Noir, swipe horizontal » : comme Strava ; × et « 3 sur 8 · date » en haut, lien vers
//                                  l'Activité en bas ; glisser vers le bas ferme.
//   B « Vertical »               : un média par écran, swipe vertical façon Reels ; auteur, titre
//                                  et lien en surimpression en bas.
//   C « Vignettes »              : swipe horizontal + bande de vignettes en bas pour sauter ;
//                                  lien vers l'Activité en haut à droite.
// La vidéo se lance avec le son dès qu'elle est à l'écran, contrôles natifs ; la carte n'est pas
// dans le visionneur (un tap sur la carte ouvre la carte plein écran).

struct ProtoViewer: View {
    static let variants = [
        ProtoVariant(key: "A", name: "Noir, swipe horizontal"),
        ProtoVariant(key: "B", name: "Vertical"),
        ProtoVariant(key: "C", name: "Vignettes"),
    ]

    let request: ProtoViewerRequest
    @Binding var variant: String
    let openActivity: (ProtoActivity) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var index: Int
    @State private var verticalID: UUID?
    @State private var drag: CGFloat = 0

    init(request: ProtoViewerRequest, variant: Binding<String>, openActivity: @escaping (ProtoActivity) -> Void) {
        self.request = request
        _variant = variant
        self.openActivity = openActivity
        _index = State(initialValue: request.start)
        _verticalID = State(initialValue: request.items[request.start].id)
    }

    private var current: ProtoViewerItem { request.items[min(index, request.items.count - 1)] }

    var body: some View {
        ZStack {
            Color.black.opacity(1 - min(abs(drag) / 400, 0.6)).ignoresSafeArea()
            switch variant {
            case "B": vertical
            case "C": withThumbnails
            default: horizontal
            }
        }
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .bottom) {
            ProtoSwitcher(title: "Visionneur", variants: Self.variants, current: $variant, showsViewerToggle: false)
                .padding(.bottom, variant == "C" ? 84 : 40)
        }
    }

    // MARK: A

    private var horizontal: some View {
        pager
            .offset(y: drag)
            .gesture(
                DragGesture()
                    .onChanged { value in if abs(value.translation.height) > abs(value.translation.width) { drag = value.translation.height } }
                    .onEnded { value in
                        if abs(value.translation.height) > 140 { dismiss() } else { withAnimation(.snappy) { drag = 0 } }
                    }
            )
            .overlay(alignment: .top) {
                HStack {
                    closeButton
                    Spacer()
                    VStack(spacing: 2) {
                        Text("\(index + 1) sur \(request.items.count)").font(.subheadline.weight(.semibold))
                        Text(current.activity.startedAt.formatted(date: .long, time: .shortened)).font(.caption)
                    }
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal)
                .opacity(drag == 0 ? 1 : 0)
            }
            .overlay(alignment: .bottom) {
                activityLink.padding(.bottom, 100).opacity(drag == 0 ? 1 : 0)
            }
    }

    // MARK: B

    private var vertical: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(request.items) { item in
                    ProtoViewerPage(media: item.media, isCurrent: verticalID == item.id)
                        .containerRelativeFrame([.horizontal, .vertical])
                        .overlay(alignment: .bottomLeading) { caption(item) }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $verticalID)
        .scrollIndicators(.hidden)
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) { closeButton.padding(.horizontal) }
        .onChange(of: verticalID) { _, id in index = request.items.firstIndex { $0.id == id } ?? index }
    }

    private func caption(_ item: ProtoViewerItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                AvatarView(name: item.activity.author.displayName, url: item.activity.author.avatarURL, size: 32)
                Text(item.activity.author.displayName).font(.subheadline.weight(.semibold))
            }
            Text(item.activity.title).font(.headline)
            Text(item.activity.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
            Button { openActivity(item.activity) } label: {
                Label("Voir l'activité", systemImage: "arrow.right").font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
        .padding()
        .padding(.bottom, 110)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
    }

    // MARK: C

    private var withThumbnails: some View {
        VStack(spacing: 0) {
            HStack {
                closeButton
                Spacer()
                Text("\(index + 1)/\(request.items.count)").font(.subheadline.weight(.semibold)).monospacedDigit()
                Spacer()
                Button { openActivity(current.activity) } label: {
                    Text("Voir l'activité").font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal)
            pager
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(Array(request.items.enumerated()), id: \.element.id) { offset, item in
                            ProtoMediaSlide(media: item.media, compact: true)
                                .frame(width: 56, height: 56)
                                .clipShape(.rect(cornerRadius: 6))
                                .overlay { RoundedRectangle(cornerRadius: 6).stroke(offset == index ? Color.white : .clear, lineWidth: 2) }
                                .opacity(offset == index ? 1 : 0.6)
                                .id(offset)
                                .onTapGesture { withAnimation { index = offset } }
                        }
                    }
                    .padding(.horizontal)
                }
                .scrollIndicators(.hidden)
                .onChange(of: index) { _, value in withAnimation { proxy.scrollTo(value, anchor: .center) } }
            }
            .frame(height: 64)
            .padding(.bottom, 8)
        }
    }

    // MARK: Pièces

    private var pager: some View {
        TabView(selection: $index) {
            ForEach(Array(request.items.enumerated()), id: \.element.id) { offset, item in
                ProtoViewerPage(media: item.media, isCurrent: offset == index).tag(offset)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    @ViewBuilder private var activityLink: some View {
        if request.showsActivityLink {
            Button { openActivity(current.activity) } label: {
                HStack(spacing: 10) {
                    Image(systemName: ActivityFormatters.sportSymbol(current.activity.sport))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(current.activity.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text("Voir l'activité").font(.caption).foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right").font(.caption.weight(.bold))
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
        } else {
            Text(current.activity.title).font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark").font(.title3.weight(.semibold)).frame(width: 44, height: 44)
        }
        .foregroundStyle(.white)
    }
}

/// Un média à l'écran, en entier (aspect fit) ; une vidéo joue avec le son quand elle est courante.
struct ProtoViewerPage: View {
    let media: ProtoMedia
    let isCurrent: Bool
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if media.kind == .video, let player {
                VideoPlayer(player: player)
                    .aspectRatio(media.aspect, contentMode: .fit)
            } else {
                ProtoMediaImage(media: media, contentMode: .fit)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if media.kind == .video, player == nil, let url = media.videoURL { player = AVPlayer(url: url) }
            if isCurrent { player?.play() }
        }
        .onChange(of: isCurrent) { _, current in
            if current { player?.play() } else { player?.pause() }
        }
        .onDisappear { player?.pause() }
    }
}
#endif
