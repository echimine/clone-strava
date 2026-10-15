// PROTOTYPE — throwaway (wayfinder #43, ticket #53 « Live Activity d'une Recording : contenu, boutons et fin de vie »).
// Three Live Activity variants switchable live from the bottom bar (← / →).
// Lock screen: ⌘L in the simulator. Dynamic Island: go home (compact), long-press it (expanded).
// Simulator: Features > Location > City Run keeps the app alive in background like a real Recording.

import ActivityKit
import SwiftUI

@main
struct PrototypeApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @State private var sim = RecordingSimulation.shared
    @State private var showGallery = ProcessInfo.processInfo.arguments.contains("-gallery")

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(sim.activitiesEnabled ? "Live Activities autorisées" : "Live Activities désactivées dans Réglages")
                        .font(.caption)
                    if sim.orphanCount > 0 {
                        Button("Ménage : terminer \(sim.orphanCount) Live Activity(s) d'avant", action: sim.cleanUpOrphans)
                    }
                }

                Section {
                    NavigationLink("Galerie : les 3 variantes côte à côte") { GalleryView(sim: sim) }
                }

                Section("Recording") {
                    Picker("Sport", selection: $sim.sport) {
                        ForEach(ProtoSport.allCases) { Text($0.label).tag($0) }
                    }
                    .disabled(sim.isRecording)
                    Toggle("Avec l'Itinéraire « \(sim.itineraryName) » (8 km)", isOn: $sim.withItinerary)
                        .disabled(sim.isRecording)
                    Toggle("Session d'arrière-plan (CLBackgroundActivitySession)", isOn: $sim.useBackgroundSession)
                        .disabled(sim.isRecording)
                    if !sim.isRecording {
                        Button("Démarrer", action: sim.start).bold()
                    } else {
                        Button(sim.isPaused ? "Reprendre" : "Pause") { sim.togglePause(from: "app") }.bold()
                        Button("+10 min d'effort", action: sim.skipTenMinutes).disabled(sim.isPaused)
                        LabeledContent("Chrono / distance", value: "\(Fmt.duration(sim.movingSeconds)) · \(Fmt.km(sim.distanceMeters)) km")
                    }
                }

                if sim.isRecording && sim.hasItinerary {
                    Section("Itinéraire") {
                        Picker("État", selection: $sim.itineraryStatus) {
                            ForEach(ItineraryStatus.allCases) { Text($0.label).tag($0) }
                        }
                        Button("Retirer l'Itinéraire", role: .destructive, action: sim.removeItinerary)
                    }
                }

                Section {
                    Picker("Rythme", selection: $sim.cadence) {
                        ForEach(RecordingSimulation.Cadence.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("staleDate", selection: $sim.staleMargin) {
                        ForEach(RecordingSimulation.StaleMargin.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("Geler les mises à jour (app tuée)", isOn: $sim.updatesFrozen)
                    LabeledContent("Mises à jour envoyées", value: "\(sim.updateCount)")
                    LabeledContent("Dernière", value: sim.lastPush?.formatted(.dateTime.hour().minute().second()) ?? "—")
                    LabeledContent("Taille de l'état", value: "\(sim.lastPayloadBytes) o / 4096")
                    LabeledContent("Positions GPS reçues", value: "\(sim.gpsFixes)")
                    LabeledContent("Dernière position", value: sim.lastFix?.formatted(.dateTime.hour().minute().second()) ?? "—")
                } header: {
                    Text("Mises à jour locales")
                } footer: {
                    Text("Le chrono avance seul (Text(timerInterval:)). Le reste n'évolue qu'à chaque mise à jour.")
                }

                if sim.isRecording {
                    Section("Fin") {
                        Picker("Retrait après Enregistrer", selection: $sim.dismissal) {
                            ForEach(RecordingSimulation.Dismissal.allCases) { Text($0.rawValue).tag($0) }
                        }
                        Button("Enregistrer", action: sim.save)
                        Button("Supprimer", role: .destructive, action: sim.discard)
                    }
                }

                Section("Journal") {
                    ForEach(Array(sim.lines.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption.monospaced())
                    }
                }
            }
            .navigationTitle("LA Recording")
            .safeAreaInset(edge: .bottom) { VariantSwitcher(variant: $sim.variant) }
            .navigationDestination(isPresented: $showGallery) { GalleryView(sim: sim) }
        }
        .task { autostartFromLaunchArguments() }
    }

    /// `-autostart [-variant B] [-sport ride] [-noItinerary]`: screenshots without tapping.
    private func autostartFromLaunchArguments() {
        let defaults = UserDefaults.standard
        guard ProcessInfo.processInfo.arguments.contains("-autostart"), !sim.isRecording else { return }
        if let v = defaults.string(forKey: "variant").flatMap(ProtoVariant.init(rawValue:)) { sim.variant = v }
        if let s = defaults.string(forKey: "sport").flatMap(ProtoSport.init(rawValue:)) { sim.sport = s }
        if ProcessInfo.processInfo.arguments.contains("-noItinerary") { sim.withItinerary = false }
        sim.start()
        sim.skipTenMinutes()
    }
}

/// Floating prototype switcher: ← / → cycle the Live Activity variant, applied immediately.
struct VariantSwitcher: View {
    @Binding var variant: ProtoVariant

    var body: some View {
        HStack(spacing: 16) {
            Button { cycle(-1) } label: { Image(systemName: "chevron.left") }
            Text("\(variant.rawValue) · \(variant.name)").font(.footnote.bold()).lineLimit(1)
            Button { cycle(1) } label: { Image(systemName: "chevron.right") }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(Capsule().fill(Color.black))
        .foregroundStyle(.white)
        .shadow(radius: 8)
        .padding(.bottom, 8)
    }

    private func cycle(_ step: Int) {
        let all = ProtoVariant.allCases
        let i = all.firstIndex(of: variant)!
        variant = all[(i + step + all.count) % all.count]
    }
}
