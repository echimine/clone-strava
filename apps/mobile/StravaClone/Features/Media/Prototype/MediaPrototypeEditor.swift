#if DEBUG
import PhotosUI
import SwiftUI

// PROTOTYPE — throwaway (see MediaPrototype.swift).
// Onglet Édition : la gestion des médias dans l'écran de fin d'enregistrement et dans la feuille
// « Modifier l'activité » (bascule en haut). Trois variantes de la section Médias :
//   A « Bande Strava »         : carte + médias en bande horizontale, tuile « Ajouter » au bout ;
//                                un tap sur un média → « Mettre en premier » / « Supprimer » ; la
//                                carte n'est que 1re ou 2e (photo mise en avant) ; « Modifier
//                                l'ordre » ouvre une liste à poignées.
//   B « Grille à glisser »     : carte et médias en grille, glisser-déposer libre, la carte comprise ;
//                                la 1re case est la couverture ; × pour supprimer.
//   C « Liste + choix de tête » : liste à poignées des médias (glisser, balayer pour supprimer),
//                                et un choix « En tête du carrousel : Carte | 1re photo ».
// La limite de 8 : le sélecteur ne laisse choisir que ce qui reste, la tuile Ajouter se grise à 8/8.

private let protoMediaLimit = 8

extension ProtoActivity {
    /// Une photo est avant la carte (« photo en premier à la place de la carte »).
    var mediaFirst: Bool { hasMap && slides.first != .map }

    func setMedia(_ media: [ProtoMedia], mediaFirst: Bool) {
        let mediaSlides = media.map(ProtoSlide.media)
        if !hasMap && route == nil {
            slides = mediaSlides
        } else if mediaFirst, let first = mediaSlides.first {
            slides = [first, .map] + mediaSlides.dropFirst()
        } else {
            slides = [.map] + mediaSlides
        }
    }

    func remove(_ media: ProtoMedia) {
        slides.removeAll { $0.media?.id == media.id }
    }

    func add(_ media: [ProtoMedia]) {
        slides += media.prefix(protoMediaLimit - self.media.count).map(ProtoSlide.media)
    }
}

struct ProtoEditorTab: View {
    let store: ProtoStore
    @AppStorage("protoEditor") private var variant = "A"
    @State private var finishScreen = true

    private static let variants = [
        ProtoVariant(key: "A", name: "Bande Strava"),
        ProtoVariant(key: "B", name: "Grille à glisser"),
        ProtoVariant(key: "C", name: "Liste + choix de tête"),
    ]

    private var activity: ProtoActivity {
        if let opened = store.openedActivity, opened.isMine { return opened }
        return store.activities[0]
    }

    var body: some View {
        NavigationStack {
            Group {
                if finishScreen { finish } else { editSheet }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Écran", selection: $finishScreen) {
                        Text("Fin d'enregistrement").tag(true)
                        Text("Modifier").tag(false)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                ProtoSwitcher(title: "Médias", variants: Self.variants, current: $variant)
            }
        }
    }

    // MARK: Fin d'enregistrement (RecordingFinishView)

    private var finish: some View {
        ScrollView {
            VStack(spacing: 20) {
                Label(ActivityFormatters.sportLabel(activity.sport), systemImage: ActivityFormatters.sportSymbol(activity.sport))
                    .font(.title3.weight(.bold))
                Text(activity.title)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                Picker("Visibilité", selection: .constant(0)) {
                    Text("Tout le monde").tag(0)
                    Text("Abonnés").tag(1)
                    Text("Moi").tag(2)
                }
                .pickerStyle(.segmented)
                ProtoMediaSection(activity: activity, variant: variant, style: .plain)
                ActivityStatsRow(post: activity.post)
                Text("Enregistrer")
                    .font(.title3.weight(.bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Theme.accent, in: Capsule())
            }
            .padding(Theme.spacing)
            .padding(.bottom, 80)
        }
    }

    // MARK: Modifier l'activité (ActivityEditSheet)

    private var editSheet: some View {
        Form {
            Section {
                TextField("Titre", text: Binding(get: { activity.title }, set: { activity.title = $0 }))
                TextField("Description", text: .constant(""), axis: .vertical).lineLimit(3 ... 8)
            }
            ProtoMediaSection(activity: activity, variant: variant, style: .form)
            Section {
                LabeledContent("Sport", value: ActivityFormatters.sportLabel(activity.sport))
                LabeledContent("Visibilité", value: "Tout le monde")
            }
        }
    }
}

// MARK: - Section Médias

struct ProtoMediaSection: View {
    enum Style { case plain, form }

    let activity: ProtoActivity
    let variant: String
    let style: Style

    @State private var picked: [PhotosPickerItem] = []
    @State private var actionTarget: ProtoMedia?
    @State private var reorders = false

    private var count: Int { activity.media.count }
    private var remaining: Int { protoMediaLimit - count }

    var body: some View {
        switch style {
        case .form:
            Section { content } header: { header } footer: { footer }
        case .plain:
            VStack(alignment: .leading, spacing: 8) {
                header.font(.subheadline.weight(.semibold))
                content
                footer.font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Photos et vidéos")
            Spacer()
            Text("\(count)/\(protoMediaLimit)").monospacedDigit().foregroundStyle(count == protoMediaLimit ? Color.red : .secondary)
        }
    }

    @ViewBuilder private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch variant {
            case "B": Text("Maintenez puis glissez pour réordonner ; la première case ouvre le carrousel.")
            case "C": Text("Glissez les poignées pour réordonner, balayez pour supprimer.")
            default: Text("Touchez un média pour le mettre en premier ou le supprimer.")
            }
            Button("Prototype : ajouter une vidéo d'exemple") {
                activity.add([.video([.jellyfish, .sintel, .bunny].randomElement()!, poster: Int.random(in: 1000 ... 1084))])
            }
            .font(.caption)
            .foregroundStyle(.purple)
            .disabled(remaining == 0)
        }
    }

    @ViewBuilder private var content: some View {
        switch variant {
        case "B": grid
        case "C": list
        default: strip
        }
    }

    // MARK: A

    private var strip: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(activity.slides) { slide in
                        tile(slide)
                            .frame(width: slide == .map ? 150 : 100, height: 110)
                            .clipShape(.rect(cornerRadius: 8))
                            .onTapGesture { actionTarget = slide.media }
                    }
                    addTile.frame(width: 110, height: 110)
                }
            }
            .scrollIndicators(.hidden)
            if count > 1 {
                Button("Modifier l'ordre") { reorders = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .confirmationDialog("Média", isPresented: Binding(get: { actionTarget != nil }, set: { if !$0 { actionTarget = nil } }), presenting: actionTarget) { media in
            if activity.hasMap {
                if activity.mediaFirst, activity.media.first?.id == media.id {
                    Button("Remettre la carte en premier") { activity.setMedia(activity.media, mediaFirst: false) }
                } else {
                    Button("Mettre en premier") { putFirst(media) }
                }
            } else if activity.media.first?.id != media.id {
                Button("Mettre en premier") { putFirst(media) }
            }
            Button("Supprimer", role: .destructive) { activity.remove(media) }
        }
        .sheet(isPresented: $reorders) {
            NavigationStack {
                List {
                    ForEach(activity.media) { media in row(media) }
                        .onMove { from, to in
                            var media = activity.media
                            media.move(fromOffsets: from, toOffset: to)
                            activity.setMedia(media, mediaFirst: activity.mediaFirst)
                        }
                }
                .environment(\.editMode, .constant(.active))
                .navigationTitle("Ordre des médias")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("OK") { reorders = false } }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func putFirst(_ media: ProtoMedia) {
        var all = activity.media
        all.removeAll { $0.id == media.id }
        activity.setMedia([media] + all, mediaFirst: true)
    }

    // MARK: B

    @State private var dragged: ProtoSlide?

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(Array(activity.slides.enumerated()), id: \.element.id) { offset, slide in
                tile(slide)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 8))
                    .overlay(alignment: .topLeading) {
                        if offset == 0, activity.slides.count > 1 {
                            Text("Couverture").font(.caption2.weight(.bold)).foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Theme.accent, in: Capsule()).padding(5)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if let media = slide.media {
                            Button { withAnimation { activity.remove(media) } } label: {
                                Image(systemName: "xmark.circle.fill").font(.title3).symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.6))
                            }
                            .buttonStyle(.plain).padding(4)
                        }
                    }
                    .onDrag {
                        dragged = slide
                        return NSItemProvider(object: slide.id as NSString)
                    }
                    .onDrop(of: [.text], delegate: ProtoReorderDrop(target: slide, activity: activity, dragged: $dragged))
            }
            addTile.aspectRatio(1, contentMode: .fit)
        }
    }

    // MARK: C

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            if activity.hasMap, count > 0 {
                Picker("En tête du carrousel", selection: Binding(
                    get: { activity.mediaFirst },
                    set: { activity.setMedia(activity.media, mediaFirst: $0) }
                )) {
                    Text("Carte").tag(false)
                    Text("1re photo").tag(true)
                }
                .pickerStyle(.segmented)
            }
            List {
                ForEach(activity.media) { media in row(media) }
                    .onMove { from, to in
                        var media = activity.media
                        media.move(fromOffsets: from, toOffset: to)
                        activity.setMedia(media, mediaFirst: activity.mediaFirst)
                    }
                    .onDelete { offsets in
                        offsets.map { activity.media[$0] }.forEach(activity.remove)
                    }
            }
            .listStyle(.plain)
            .environment(\.editMode, .constant(.active))
            .frame(height: CGFloat(max(count, 1)) * 64)
            addTile.frame(height: 50)
        }
    }

    // MARK: Pièces

    @ViewBuilder private func tile(_ slide: ProtoSlide) -> some View {
        switch slide {
        case .map:
            ProtoMapSlide(route: activity.route, sport: activity.sport)
                .overlay(alignment: .bottomLeading) {
                    Label("Carte", systemImage: "map").font(.caption2.weight(.bold)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.black.opacity(0.55), in: Capsule()).padding(5)
                }
        case .media(let media):
            ProtoMediaSlide(media: media, compact: true)
        }
    }

    private func row(_ media: ProtoMedia) -> some View {
        HStack(spacing: 12) {
            ProtoMediaSlide(media: media, compact: true).frame(width: 52, height: 52).clipShape(.rect(cornerRadius: 6))
            VStack(alignment: .leading) {
                Text(media.kind == .photo ? "Photo" : "Vidéo")
                if let seconds = media.durationSeconds { Text(seconds.protoDuration).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    private var addTile: some View {
        let remaining = remaining
        return PhotosPicker(selection: $picked, maxSelectionCount: max(remaining, 1), selectionBehavior: .ordered, matching: .any(of: [.images, .videos])) {
            VStack(spacing: 6) {
                Image(systemName: remaining == 0 ? "photo.badge.exclamationmark" : "photo.badge.plus").font(.title3)
                Text(remaining == 0 ? "Limite de 8 atteinte" : "Ajouter photos/vidéo")
                    .font(.caption.weight(.semibold)).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 8))
            .foregroundStyle(remaining == 0 ? Color.secondary : Color.primary)
        }
        .disabled(remaining == 0)
        .buttonStyle(.plain)
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            Task { await load(items) }
        }
    }

    private func load(_ items: [PhotosPickerItem]) async {
        var added: [ProtoMedia] = []
        for item in items {
            if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                added.append(.video(.bunny, poster: Int.random(in: 1000 ... 1084)))
            } else if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                added.append(ProtoMedia(kind: .photo, localImage: image, aspect: image.size.width / max(image.size.height, 1)))
            }
        }
        withAnimation { activity.add(added) }
        picked = []
    }
}

/// Glisser-déposer de la variante B : la case survolée prend la place de la case tenue.
private struct ProtoReorderDrop: DropDelegate {
    let target: ProtoSlide
    let activity: ProtoActivity
    @Binding var dragged: ProtoSlide?

    func dropEntered(info: DropInfo) {
        guard let dragged, dragged != target,
              let from = activity.slides.firstIndex(of: dragged),
              let to = activity.slides.firstIndex(of: target) else { return }
        withAnimation(.snappy) {
            activity.slides.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragged = nil
        return true
    }
}
#endif
