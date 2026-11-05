#if DEBUG
import SwiftUI

// PROTOTYPE — throwaway (voir SegmentProto.swift).
// Aperçu de la portion, nom, création ; réponses simulées : créé, doublon, quota.

struct ProtoPreviewView: View {
    let store: ProtoStore
    let portion: ProtoPortion
    /// Activité d'origine, ou nil pour un Segment dessiné.
    let sourceTitle: String?
    let onFinish: () -> Void

    @State private var name = ""
    @State private var result: ProtoCreateResult?
    @State private var showsDuplicate = false
    @FocusState private var isNameFocused: Bool

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isNameValid: Bool { (3...60).contains(trimmed.count) }

    var body: some View {
        if result == .created {
            ProtoCreatedView(name: trimmed, portion: portion, onDone: onFinish, onMine: {
                store.selectedTab = .mine
                onFinish()
            })
        } else {
            form
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                ProtoPortionMiniMap(coordinates: portion.coordinates)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                HStack(spacing: 6) {
                    Label(portion.sport.label, systemImage: portion.sport.symbol)
                        .font(.subheadline.weight(.semibold))
                    if let sourceTitle {
                        Text("· extrait de « \(sourceTitle) »").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    } else {
                        Text("· dessiné sur la carte").font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                ProtoPortionStats(portion: portion)

                ElevationProfileChart(profile: portion.profile)
                    .frame(height: 120)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Nom du Segment").font(.headline)
                    TextField("Ex. : Montée du col de la Forclaz", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .focused($isNameFocused)
                        .submitLabel(.done)
                    HStack {
                        Text(trimmed.count < 3 && !name.isEmpty ? "3 caractères au moins." : " ")
                            .foregroundStyle(.orange)
                        Spacer()
                        Text("\(trimmed.count)/60").foregroundStyle(trimmed.count > 60 ? .red : .secondary)
                    }
                    .font(.caption)
                }

                if case .duplicate(let existing) = result {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Ce Segment existe déjà", systemImage: "square.on.square").font(.subheadline.bold())
                        Text("« \(existing) » suit le même tracé. Tes passages y sont déjà comptés.")
                            .font(.footnote)
                        Button("Voir « \(existing) »") { showsDuplicate = true }
                            .font(.footnote.bold())
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                }
                if result == .quota {
                    Label {
                        Text("Tu as créé 10 Segments ces dernières 24 h. Tu pourras en créer un autre à partir de \(Date.now.addingTimeInterval(4 * 3_600).formatted(date: .omitted, time: .shortened)).")
                            .font(.footnote)
                    } icon: {
                        Image(systemName: "hourglass")
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }

                Text("Un Segment est public : tous les athlètes qui passent dessus sont classés. Ton nom n'est jamais affiché comme créateur. Le tracé ne pourra plus être modifié.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(Theme.spacing)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Nouveau Segment")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                isNameFocused = false
                withAnimation { result = store.create(name: trimmed, portion: portion) }
            } label: {
                Text("Créer le Segment").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isNameValid)
            .padding(Theme.spacing)
            .background(.bar)
        }
        .sheet(isPresented: $showsDuplicate) {
            NavigationStack {
                ContentUnavailableView(
                    "Col de la Forclaz depuis Talloires",
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                    description: Text("Fiche du Segment : prototype « fiche d'un Segment » (#238).")
                )
                .toolbar { Button("Fermer") { showsDuplicate = false } }
            }
            .presentationDetents([.medium])
        }
    }
}

struct ProtoCreatedView: View {
    let name: String
    let portion: ProtoPortion
    let onDone: () -> Void
    let onMine: () -> Void

    var body: some View {
        VStack(spacing: Theme.spacing) {
            Spacer()
            Image(systemName: "checkmark.seal.fill").font(.system(size: 56)).foregroundStyle(Theme.accent)
            Text("Segment créé").font(.title2.bold())
            Text("« \(name) »").font(.headline)
            Text("\(ProtoFormat.distance(portion.meters)) · \(ProtoFormat.grade(portion.averageGrade))\(portion.category.map { " · \($0)" } ?? "")")
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ProgressView()
                Text("On cherche tes passages et ceux des autres athlètes. Le classement se remplit dans quelques minutes.")
                    .font(.footnote)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            Spacer()
            Button(action: onMine) {
                Text("Voir mes Segments").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            Button(action: onDone) {
                Text("Terminé").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(Theme.spacing)
        .navigationBarBackButtonHidden()
    }
}
#endif
