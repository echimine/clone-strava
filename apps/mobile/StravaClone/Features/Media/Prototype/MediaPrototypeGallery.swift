#if DEBUG
import SwiftUI

// PROTOTYPE — throwaway (see MediaPrototype.swift).
// Onglet Profil : la vraie barre d'onglets du profil, avec la Galerie. Quatre variantes :
//   A « Grille 3 colonnes »   : carrés serrés, du plus récent au plus ancien, durée sur les vidéos.
//   B « Par Activité »        : une section par Activité (sport, titre, date ; tap → l'Activité),
//                               ses médias en grille dessous.
//   C « Grille / Liste »      : comme Strava, bascule Grille | Liste ; la liste montre chaque média
//                               en grand avec le titre de son Activité.
//   D « Bande sous l'en-tête » : pas d'onglet Galerie ; les derniers médias en bande sous l'en-tête
//                               du profil (comme Strava) et « Tout voir » ouvre la grille.
// Un tap ouvre le visionneur sur tous les médias de l'athlète, avec le lien vers l'Activité.

enum ProtoProfileTabKind: Hashable { case progress, activities, gallery, more }

struct ProtoProfileTab: View {
    let store: ProtoStore
    @AppStorage("protoGallery") private var variant = "A"
    @State private var athlete = ActivityAuthor.protoMe
    @State private var tab = ProtoProfileTabKind.gallery
    @State private var showsAllMedia = false

    private static let variants = [
        ProtoVariant(key: "A", name: "Grille 3 colonnes"),
        ProtoVariant(key: "B", name: "Par Activité"),
        ProtoVariant(key: "C", name: "Grille / Liste"),
        ProtoVariant(key: "D", name: "Bande sous l'en-tête"),
    ]

    private var items: [ProtoViewerItem] { store.galleryItems(of: athlete) }
    private var tabs: [ProtoProfileTabKind] {
        variant == "D" ? [.progress, .activities, .more] : [.progress, .activities, .gallery, .more]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    header
                    if variant == "D" { strip }
                    LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                        Section {
                            content.padding(.top, 2)
                        } header: {
                            ProfileTabBar(tabs: tabs, selection: $tab, title: title, systemImage: symbol)
                        }
                    }
                }
                .padding(.bottom, 80)
            }
            .navigationTitle(athlete.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Picker("Profil", selection: $athlete) {
                        Text("Moi").tag(ActivityAuthor.protoMe)
                        Text("Camille").tag(ActivityAuthor.protoCamille)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .safeAreaInset(edge: .bottom) {
                ProtoSwitcher(title: "Galerie", variants: Self.variants, current: $variant)
            }
            .onChange(of: variant) { _, value in if value == "D", tab == .gallery { tab = .activities } }
            .navigationDestination(isPresented: $showsAllMedia) {
                ScrollView { ProtoGalleryGrid(items: items, open: open) }
                    .navigationTitle("Photos et vidéos")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            AvatarView(name: athlete.displayName, url: athlete.avatarURL, size: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text(athlete.displayName).font(.title3.weight(.bold))
                Text("\(items.count) photos et vidéos · \(store.activities.filter { $0.author == athlete }.count) activités")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(Theme.spacing)
    }

    private var strip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(Array(items.prefix(4).enumerated()), id: \.element.id) { offset, item in
                    ProtoMediaSlide(media: item.media, compact: true)
                        .frame(width: 96, height: 96)
                        .clipShape(.rect(cornerRadius: 8))
                        .onTapGesture { open(offset) }
                }
                if items.count > 4 {
                    Button { showsAllMedia = true } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "square.grid.3x3")
                            Text("Tout voir").font(.caption.weight(.semibold))
                        }
                        .frame(width: 96, height: 96)
                        .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.spacing)
        }
        .scrollIndicators(.hidden)
        .padding(.bottom, Theme.spacing)
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .gallery:
            if items.isEmpty {
                ContentUnavailableView("Aucune photo ni vidéo", systemImage: "photo.on.rectangle", description: Text("Les photos et vidéos des activités apparaîtront ici."))
                    .padding(.top, 40)
            } else {
                switch variant {
                case "B": ProtoGalleryByActivity(store: store, items: items, open: open)
                case "C": ProtoGalleryGridOrList(items: items, open: open)
                default: ProtoGalleryGrid(items: items, open: open)
                }
            }
        case .activities:
            LazyVStack(spacing: Theme.spacing) {
                ForEach(store.activities.filter { $0.author == athlete }.sorted { $0.startedAt > $1.startedAt }) { activity in
                    ProtoActivityCard(store: store, activity: activity, variant: UserDefaults.standard.string(forKey: "protoFeed") ?? "A")
                }
            }
            .padding(Theme.spacing)
            .background(Color(.systemGroupedBackground))
        default:
            Text("Hors prototype").foregroundStyle(.secondary).padding(.top, 40)
        }
    }

    private func open(_ offset: Int) {
        store.viewer = ProtoViewerRequest(items: items, start: offset, showsActivityLink: true)
    }

    private func title(_ tab: ProtoProfileTabKind) -> String {
        switch tab {
        case .progress: "Progrès"
        case .activities: "Activités"
        case .gallery: "Galerie"
        case .more: "Plus"
        }
    }

    private func symbol(_ tab: ProtoProfileTabKind) -> String {
        switch tab {
        case .progress: "chart.bar.doc.horizontal"
        case .activities: "waveform.path.ecg"
        case .gallery: "photo.on.rectangle"
        case .more: "line.3.horizontal"
        }
    }
}

// MARK: - A

struct ProtoGalleryGrid: View {
    let items: [ProtoViewerItem]
    let open: (Int) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                ProtoGalleryTile(media: item.media).onTapGesture { open(offset) }
            }
        }
    }
}

struct ProtoGalleryTile: View {
    let media: ProtoMedia

    var body: some View {
        ProtoMediaImage(media: media)
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .topTrailing) {
                if media.kind == .video {
                    HStack(spacing: 3) {
                        Image(systemName: "play.fill")
                        Text((media.durationSeconds ?? 0).protoDuration).monospacedDigit()
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
                    .padding(6)
                }
            }
            .contentShape(.rect)
    }
}

// MARK: - B

struct ProtoGalleryByActivity: View {
    let store: ProtoStore
    let items: [ProtoViewerItem]
    let open: (Int) -> Void

    var body: some View {
        let groups = Dictionary(grouping: Array(items.enumerated()), by: { $0.element.activity.id })
        let activities = items.map(\.activity).reduce(into: [ProtoActivity]()) { result, activity in
            if !result.contains(where: { $0.id == activity.id }) { result.append(activity) }
        }
        LazyVStack(alignment: .leading, spacing: Theme.spacing) {
            ForEach(activities) { activity in
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        store.openedActivity = activity
                        store.selectedTab = .detail
                    } label: {
                        HStack {
                            Image(systemName: ActivityFormatters.sportSymbol(activity.sport)).foregroundStyle(Theme.accent)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(activity.title).font(.subheadline.weight(.semibold))
                                Text(activity.startedAt.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, Theme.spacing)
                    }
                    .buttonStyle(.plain)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                        ForEach(groups[activity.id] ?? [], id: \.element.id) { offset, item in
                            ProtoGalleryTile(media: item.media).onTapGesture { open(offset) }
                        }
                    }
                }
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - C

struct ProtoGalleryGridOrList: View {
    let items: [ProtoViewerItem]
    let open: (Int) -> Void
    @State private var showsList = false

    var body: some View {
        VStack(spacing: 8) {
            Picker("Affichage", selection: $showsList) {
                Text("Grille").tag(false)
                Text("Liste").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.spacing)
            .padding(.top, 8)
            if showsList {
                LazyVStack(spacing: 12) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                        ProtoMediaSlide(media: item.media)
                            .aspectRatio(item.media.aspect, contentMode: .fit)
                            .overlay(alignment: .bottomLeading) {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(item.activity.title).font(.subheadline.weight(.semibold))
                                    Text(item.activity.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                                }
                                .foregroundStyle(.white)
                                .shadow(radius: 3)
                                .padding(10)
                            }
                            .onTapGesture { open(offset) }
                    }
                }
            } else {
                ProtoGalleryGrid(items: items, open: open)
            }
        }
    }
}
#endif
