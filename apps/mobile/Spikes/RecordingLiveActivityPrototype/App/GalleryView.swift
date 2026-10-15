// PROTOTYPE — throwaway (wayfinder #43, ticket #53). Never merged.
// The three variants side by side, drawn from the same views as the widget with the live simulated state.
// An approximation of the system chrome: the real Live Activity (lock screen, island) stays the reference.

import SwiftUI

struct GalleryView: View {
    let sim: RecordingSimulation

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if !sim.isRecording {
                        Text("Démarre une Recording pour des valeurs vivantes.").font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(ProtoVariant.allCases.filter { UserDefaults.standard.string(forKey: "only").map($0.rawValue.elementsEqual) ?? true }) { v in
                        variantBlock(v, sim.previewState(v))
                    }
                }
                .padding()
            }
            .background(Color(white: 0.12))
        }
        .navigationTitle("Galerie")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func variantBlock(_ v: ProtoVariant, _ s: LAState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(v.rawValue) · \(v.name)").font(.headline).foregroundStyle(.white)

            caption("Écran verrouillé")
            LockScreenContent(sport: sim.sport, s: s, isStale: false)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 22).fill(Parts.lockTint(s)))

            caption("Île compacte · minimale")
            HStack(spacing: 16) {
                HStack {
                    Parts.compactLeading(v, sim.sport, s)
                    Spacer(minLength: 110)
                    Parts.compactTrailing(v, sim.sport, s)
                }
                .padding(.horizontal, 14).frame(height: 36)
                .background(Capsule().fill(.black))
                Parts.minimal(v, sim.sport, s)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.black))
            }
            .foregroundStyle(.white)

            caption("Île étendue")
            VStack(spacing: 8) {
                HStack(alignment: .top) {
                    Parts.expandedLeading(v, sim.sport, s)
                    Spacer()
                    Parts.expandedCenter(v, sim.sport, s)
                    Spacer()
                    Parts.expandedTrailing(v, sim.sport, s)
                }
                Parts.expandedBottom(v, sim.sport, s)
            }
            .foregroundStyle(.white)
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 40).fill(.black))
        }
        .environment(\.colorScheme, .dark)
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.gray)
    }
}
