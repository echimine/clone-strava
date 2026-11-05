#if DEBUG
import SwiftUI

// PROTOTYPE — throwaway (voir SegmentProto.swift).
// Les quatre onglets, les points d'entrée et « Mes Segments ».

struct SegmentCreationPrototypeView: View {
    @State private var store = ProtoStore()

    var body: some View {
        @Bindable var store = store
        TabView(selection: $store.selectedTab) {
            ProtoEntriesTab(store: store)
                .tabItem { Label("Entrées", systemImage: "door.left.hand.open") }
                .tag(ProtoTab.entries)
            ProtoExtractFlow(store: store)
                .tabItem { Label("Extraire", systemImage: "scissors") }
                .tag(ProtoTab.extract)
            ProtoDrawFlow(store: store)
                .tabItem { Label("Dessiner", systemImage: "pencil.and.outline") }
                .tag(ProtoTab.draw)
            ProtoMySegmentsView(store: store)
                .tabItem { Label("Mes Segments", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                .tag(ProtoTab.mine)
        }
        .overlay(alignment: .topLeading) { serverMenu }
        .fullScreenCover(item: $store.flow) { flow in
            switch flow {
            case .extract: ProtoExtractFlow(store: store, showsSwitcher: true, onClose: { store.flow = nil })
            case .draw: ProtoDrawFlow(store: store, onClose: { store.flow = nil })
            case .pickActivity: ProtoActivityPicker(onPick: { store.flow = .extract }, onClose: { store.flow = nil })
            }
        }
    }

    /// Réponse simulée du serveur à « Créer le Segment ».
    private var serverMenu: some View {
        Menu {
            Picker("Réponse du serveur", selection: Bindable(store).reply) {
                ForEach(ProtoServerReply.allCases) { Text($0.rawValue).tag($0) }
            }
        } label: {
            Label("Serveur : \(store.reply.rawValue)", systemImage: "server.rack")
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color.purple.opacity(0.9), in: Capsule())
        }
        .padding(.leading, 8)
        .padding(.top, 2)
    }
}

// MARK: - Points d'entrée

struct ProtoEntriesTab: View {
    let store: ProtoStore

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(ProtoTrack.sample.title, systemImage: "bicycle").font(.headline)
                            Spacer()
                            Menu {
                                Button("Modifier", systemImage: "pencil") {}
                                Button("Ajouter des photos ou vidéos", systemImage: "photo.badge.plus") {}
                                Button("Créer un Segment", systemImage: "point.topleft.down.to.point.bottomright.curvepath") { store.flow = .extract }
                                Button("Supprimer", systemImage: "trash", role: .destructive) {}
                            } label: {
                                Image(systemName: "ellipsis.circle").font(.title3)
                            }
                        }
                        ProtoPortionMiniMap(coordinates: ProtoTrack.sample.points.map(\.coordinate))
                            .frame(height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .allowsHitTesting(false)
                        Button {
                            store.flow = .extract
                        } label: {
                            Label("Créer un Segment depuis cette Activité", systemImage: "scissors")
                        }
                        .font(.subheadline)
                    }
                } header: {
                    Text("1. Détail d'une de mes Activités")
                } footer: {
                    Text("Menu « … » du détail (à côté de Modifier) ou lien sous la carte. Seulement sur ses Activités avec trace GPS ; pas sur une Activité manuelle ni une natation en piscine.")
                }

                Section {
                    HStack {
                        Text("Carte").foregroundStyle(.secondary)
                        Spacer()
                        Menu {
                            Button("Un Itinéraire", systemImage: "map") {}
                            Button("Un Segment", systemImage: "point.topleft.down.to.point.bottomright.curvepath") { store.flow = .draw }
                        } label: {
                            Label("Créer", systemImage: "plus")
                                .font(.subheadline.bold())
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(Color(.secondarySystemBackground), in: Capsule())
                        }
                        .foregroundStyle(Theme.accent)
                    }
                } header: {
                    Text("2. Bouton « Créer » de l'onglet Carte")
                } footer: {
                    Text("Le bouton qui crée aujourd'hui un Itinéraire devient un menu : Itinéraire ou Segment. Le Segment s'y dessine avec l'éditeur d'Itinéraire.")
                }

                Section {
                    HStack {
                        Text("Mes Segments").font(.headline)
                        Spacer()
                        Menu {
                            Button("Dessiner sur la carte", systemImage: "pencil.and.outline") { store.flow = .draw }
                            Button("À partir d'une Activité", systemImage: "scissors") { store.flow = .pickActivity }
                        } label: {
                            Image(systemName: "plus.circle.fill").font(.title2)
                        }
                    }
                } header: {
                    Text("3. « Mes Segments » (profil › Plus)")
                } footer: {
                    Text("Le « + » propose les deux façons ; « À partir d'une Activité » ouvre la liste de ses Activités avec trace.")
                }
            }
            .navigationTitle("Où créer un Segment")
        }
    }
}

/// « À partir d'une Activité » : ses Activités, celles sans trace grisées.
struct ProtoActivityPicker: View {
    let onPick: () -> Void
    let onClose: () -> Void

    private let rows: [(String, String, String, Bool)] = [
        ("Annecy – col de la Forclaz", "bicycle", "Hier · 23,70 km", true),
        ("Footing du Pâquier", "figure.run", "Il y a 3 j · 8,12 km · Privée", true),
        ("Piscine Jean Régis", "figure.pool.swim", "Il y a 4 j · 1 500 m · piscine, sans trace", false),
        ("Home trainer", "bicycle", "Il y a 6 j · manuelle, sans trace", false),
        ("Semnoz par les crêtes", "figure.hiking", "Il y a 9 j · 14,30 km", true),
    ]

    var body: some View {
        NavigationStack {
            List(rows, id: \.0) { row in
                Button(action: onPick) {
                    HStack {
                        Image(systemName: row.1).frame(width: 28)
                        VStack(alignment: .leading) {
                            Text(row.0)
                            Text(row.2).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(!row.3)
                .foregroundStyle(.primary)
            }
            .navigationTitle("Choisis une Activité")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler", action: onClose) } }
        }
    }
}

// MARK: - Mes Segments

struct ProtoMySegmentsView: View {
    @Bindable var store: ProtoStore
    @State private var renaming: ProtoMySegment?
    @State private var newName = ""
    @State private var deleting: ProtoMySegment?
    @State private var blocked: ProtoMySegment?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.mySegments) { segment in
                        row(segment)
                            .swipeActions {
                                Button("Supprimer", systemImage: "trash") { delete(segment) }.tint(.red)
                                Button("Renommer", systemImage: "pencil") { rename(segment) }.tint(.blue)
                            }
                            .contextMenu {
                                Button("Renommer", systemImage: "pencil") { rename(segment) }
                                Button("Supprimer", systemImage: "trash", role: .destructive) { delete(segment) }
                            }
                    }
                } footer: {
                    Text("Visible par toi seul. \(store.createdToday) Segment(s) créé(s) ces dernières 24 h sur 10. Glisse une ligne ou appuie longuement pour renommer ou supprimer.")
                }
            }
            .navigationTitle("Mes Segments")
            .toolbar {
                Menu {
                    Button("Dessiner sur la carte", systemImage: "pencil.and.outline") { store.flow = .draw }
                    Button("À partir d'une Activité", systemImage: "scissors") { store.flow = .pickActivity }
                } label: {
                    Label("Créer", systemImage: "plus")
                }
            }
            .alert("Renommer le Segment", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Nom", text: $newName)
                Button("Annuler", role: .cancel) {}
                Button("Renommer") {
                    let trimmed = newName.trimmingCharacters(in: .whitespaces)
                    if let index = store.mySegments.firstIndex(where: { $0.id == renaming?.id }), (3...60).contains(trimmed.count) {
                        store.mySegments[index].name = trimmed
                    }
                }
            } message: {
                Text("De 3 à 60 caractères. Le nouveau nom s'affiche partout, classement compris.")
            }
            .confirmationDialog("Supprimer « \(deleting?.name ?? "") » ?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Supprimer le Segment", role: .destructive) {
                    store.mySegments.removeAll { $0.id == deleting?.id }
                }
            } message: {
                Text("Tes Efforts et ton classement sur ce Segment disparaissent.")
            }
            .alert("Suppression impossible", isPresented: Binding(get: { blocked != nil }, set: { if !$0 { blocked = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("\(blocked?.otherAthletes ?? 0) autres athlètes ont un Effort sur « \(blocked?.name ?? "") ». Tu peux encore le renommer ; pour le faire retirer, signale-le.")
            }
        }
    }

    private func row(_ segment: ProtoMySegment) -> some View {
        HStack(spacing: 12) {
            Image(systemName: segment.sport.symbol)
                .frame(width: 36, height: 36)
                .background(Theme.accent.opacity(0.12), in: Circle())
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(segment.name).font(.headline)
                Text("\(ProtoFormat.distance(segment.meters)) · \(ProtoFormat.grade(segment.grade))\(segment.category.map { " · \($0)" } ?? "")")
                    .font(.caption).foregroundStyle(.secondary)
                if segment.isMatching {
                    Label("Recherche des passages…", systemImage: "hourglass").font(.caption2).foregroundStyle(Theme.accent)
                } else {
                    Text(segment.otherAthletes == 0 ? "Personne d'autre pour l'instant" : "\(segment.otherAthletes + 1) athlètes classés")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
    }

    private func rename(_ segment: ProtoMySegment) {
        newName = segment.name
        renaming = segment
    }

    private func delete(_ segment: ProtoMySegment) {
        if segment.otherAthletes > 0 { blocked = segment } else { deleting = segment }
    }
}
#endif
