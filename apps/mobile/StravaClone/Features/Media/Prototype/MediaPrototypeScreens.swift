#if DEBUG
import SwiftUI

// PROTOTYPE — throwaway (see MediaPrototype.swift).
// Onglets Fil et Détail : les vrais en-tête, stats et barre sociale de la carte d'Activité,
// le carrousel du prototype à la place de la carte statique.

// MARK: - Carte d'Activité

struct ProtoActivityCard: View {
    let store: ProtoStore
    let activity: ProtoActivity
    let variant: String

    var body: some View {
        let post = activity.post
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                ActivityCardHeader(post: post)
                Text(post.title).font(.title3.weight(.bold)).lineLimit(2)
                ActivityStatsRow(post: post).padding(.horizontal, -8)
            }
            .padding([.horizontal, .top], Theme.spacing)

            ProtoCarousel(
                activity: activity,
                variant: variant,
                height: 250,
                onTapMedia: { store.openViewer(activity, at: $0) },
                onTapMap: { open() }
            )

            ActivitySocialBar(post: post, onToggleKudos: { activity.engagement = activity.engagement.togglingKudos() }, onComments: {})
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
        }
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        .clipShape(.rect(cornerRadius: 20))
        .contentShape(.rect(cornerRadius: 20))
        .onTapGesture { open() }
    }

    private func open() {
        store.openedActivity = activity
        store.selectedTab = .detail
    }
}

// MARK: - Fil

struct ProtoFeedTab: View {
    let store: ProtoStore
    @AppStorage("protoFeed") private var variant = "A"

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: Theme.spacing) {
                    ForEach(store.activities.sorted { $0.startedAt > $1.startedAt }) { activity in
                        ProtoActivityCard(store: store, activity: activity, variant: variant)
                    }
                }
                .padding(.horizontal, Theme.spacing)
                .padding(.bottom, 80)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Accueil")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                ProtoSwitcher(title: "Carrousel", variants: ProtoCarouselVariants.all, current: $variant)
            }
        }
    }
}

// MARK: - Détail

struct ProtoDetailTab: View {
    @Bindable var store: ProtoStore
    @AppStorage("protoDetail") private var variant = "A"
    @State private var showsMap = false

    private var activity: ProtoActivity {
        store.openedActivity ?? store.activities[0]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacing) {
                    ProtoCarousel(
                        activity: activity,
                        variant: variant,
                        height: 330,
                        insetsSlides: false,
                        onTapMedia: { store.openViewer(activity, at: $0) },
                        onTapMap: { showsMap = activity.route != nil }
                    )
                    .id(activity.id)
                    VStack(alignment: .leading, spacing: Theme.spacing) {
                        ActivityCardHeader(post: activity.post)
                        Text(activity.title).font(.title2.weight(.bold))
                        ActivityStatsRow(post: activity.post)
                        Text("Un tap sur la carte ouvre la carte plein écran ; sur un média, le visionneur.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, Theme.spacing)
                }
                .padding(.bottom, 80)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(ActivityFormatters.sportLabel(activity.sport))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ForEach(store.activities) { item in
                            Button("\(item.title) (\(item.slides.count))") { store.openedActivity = item }
                        }
                    } label: {
                        Label("Activité", systemImage: "list.bullet")
                    }
                }
                if activity.isMine {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Ajouter des photos ou vidéos", systemImage: "photo.badge.plus") { openEditor() }
                            Button("Modifier", systemImage: "pencil") { openEditor() }
                            Button("Supprimer", systemImage: "trash", role: .destructive) {}
                        } label: {
                            Label("Gérer", systemImage: "ellipsis")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                ProtoSwitcher(title: "En-tête", variants: ProtoCarouselVariants.all, current: $variant)
            }
            .fullScreenCover(isPresented: $showsMap) {
                if let route = activity.route {
                    ActivityFullScreenMap(route: route, routeTrimmed: false, post: activity.post)
                }
            }
        }
    }

    private func openEditor() {
        store.openedActivity = activity
        store.selectedTab = .editor
    }
}
#endif
