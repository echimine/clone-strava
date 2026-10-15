// PROTOTYPE — throwaway (wayfinder #43, ticket #50 « Écran d'une Recording en cours »).
// Three structurally different layouts of the in-progress Recording screen on the
// Enregistrer tab, switched by the top pill (‹ ›), the variant remembered across launches.
// The ⚙︎ button forces any state: sport, Pause, Itinerary state, GPS. DEBUG builds only.

import MapboxMaps
import SwiftUI

struct RecordingPrototypeScreen: View {
    static let variants = ["A", "B", "C"]
    static let names = ["A": "Stats d'abord, bascule carte", "B": "Carte d'abord, panneau", "C": "Écran partagé fixe"]

    @AppStorage("prototype.recordingVariant") private var variant = "A"
    @State private var sim = RecordingPrototypeSimulation()
    @State private var showsScenario = false
    @State private var showsEndScreen = false

    var body: some View {
        Group {
            switch variant {
            case "B": RecordingVariantB(sim: sim, onFinish: finish)
            case "C": RecordingVariantC(sim: sim, onFinish: finish)
            default: RecordingVariantA(sim: sim, onFinish: finish)
            }
        }
        .overlay(alignment: .top) { switcher }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                sim.tick()
            }
        }
        .sheet(isPresented: $showsScenario) { RecordingPrototypeScenarioPanel(sim: sim) }
        .sheet(isPresented: $showsEndScreen) {
            ContentUnavailableView(
                "Écran de fin",
                systemImage: "flag.checkered",
                description: Text("Hors de ce prototype : « Écran de fin : titre, visibilité, Recording trop courte » (#51).")
            )
            .presentationDetents([.medium])
        }
    }

    private func finish() {
        sim.pause()
        showsEndScreen = true
    }

    private var switcher: some View {
        HStack(spacing: 12) {
            Button { cycle(-1) } label: { Image(systemName: "chevron.left") }
            Text("\(variant) · \(Self.names[variant] ?? "")")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Button { cycle(1) } label: { Image(systemName: "chevron.right") }
            Divider().frame(height: 16).overlay(.white.opacity(0.5))
            Button { showsScenario = true } label: { Image(systemName: "slider.horizontal.3") }
        }
        .font(.callout.weight(.bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.purple.opacity(0.92), in: Capsule())
        .shadow(radius: 4)
        .padding(.top, 2)
    }

    private func cycle(_ step: Int) {
        let index = Self.variants.firstIndex(of: variant) ?? 0
        variant = Self.variants[(index + step + Self.variants.count) % Self.variants.count]
    }
}

// MARK: Scenario panel

struct RecordingPrototypeScenarioPanel: View {
    @Bindable var sim: RecordingPrototypeSimulation

    var body: some View {
        NavigationStack {
            Form {
                Picker("Sport", selection: $sim.sport) {
                    ForEach(RecordingPrototypeSimulation.sports, id: \.self) { sport in
                        Label(ActivityFormatters.sportLabel(sport), systemImage: ActivityFormatters.sportSymbol(sport))
                            .tag(sport)
                    }
                }
                Picker("Phase", selection: $sim.phase) {
                    ForEach(RecordingPrototypeSimulation.Phase.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("GPS", selection: $sim.gps) {
                    ForEach(RecordingPrototypeSimulation.GPS.allCases) { Text($0.rawValue).tag($0) }
                }
                Section("Itinéraire") {
                    Toggle("Itinéraire suivi", isOn: $sim.hasItinerary)
                    Picker("État", selection: Binding(get: { sim.itineraryState }, set: { sim.setItineraryState($0) })) {
                        ForEach(RecordingPrototypeSimulation.ItineraryState.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .disabled(!sim.hasItinerary)
                }
                Section("État complet") {
                    Text(sim.stateDump).font(.caption.monospaced())
                }
            }
            .navigationTitle("Scénario")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: Shared pieces (kept small on purpose: each variant owns its layout)

/// Map of the Recording: Itinerary underneath, recorded trace, recalculated path, position.
/// Follows the athlete; gestures off for the prototype.
struct RecordingPrototypeMap: View {
    let sim: RecordingPrototypeSimulation
    var zoom: Double = 15.3

    var body: some View {
        let position = sim.position.locationCoordinate
        Map(viewport: .constant(.camera(center: position, zoom: zoom))) {
            if sim.hasItinerary {
                PolylineAnnotation(lineCoordinates: sim.loop.map(\.locationCoordinate))
                    .lineColor(UIColor(Theme.accent).withAlphaComponent(0.35))
                    .lineWidth(8)
                    .lineJoin(.round)
                RouteEndpointsContent(coordinates: sim.loop.map(\.locationCoordinate))
            }
            if sim.trace.count >= 2 {
                PolylineAnnotation(lineCoordinates: sim.trace.map(\.locationCoordinate))
                    .lineColor(UIColor(Theme.accent))
                    .lineWidth(4)
                    .lineJoin(.round)
            }
            if sim.reroute.count >= 2 {
                PolylineAnnotationGroup([sim.reroute], id: \.self) { line in
                    PolylineAnnotation(lineCoordinates: line.map(\.locationCoordinate))
                        .lineColor(.systemBlue)
                        .lineWidth(5)
                }
                .lineDashArray([1, 1.2])
                .lineCap(.round)
            }
            MapViewAnnotation(coordinate: position) {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(.white, lineWidth: 3))
                    .shadow(radius: 2)
            }
            .allowOverlap(true)
        }
        .mapStyle(.outdoors)
        .gestureOptions(GestureOptions(panEnabled: false, pinchEnabled: false, rotateEnabled: false))
    }
}

struct RecordingGPSChip: View {
    let gps: RecordingPrototypeSimulation.GPS

    var body: some View {
        Label(gps.rawValue, systemImage: gps == .ready ? "location.fill" : "location.slash")
            .font(.caption.weight(.semibold))
            .foregroundStyle(gps == .ready ? .green : gps == .weak ? .orange : .red)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassBackground(in: Capsule())
    }
}

/// The value / unit / label trio every variant arranges its own way.
struct RecordingStat: Identifiable {
    let label: String
    let value: String
    let unit: String
    var id: String { label }

    @MainActor static func all(_ sim: RecordingPrototypeSimulation) -> [RecordingStat] {
        if sim.isOnFoot {
            return [
                RecordingStat(label: "Temps", value: sim.chronoText, unit: ""),
                RecordingStat(label: "Distance", value: sim.distanceText, unit: "km"),
                RecordingStat(label: "Allure moy.", value: sim.averagePaceText, unit: "/km"),
            ]
        }
        return [
            RecordingStat(label: "Temps", value: sim.chronoText, unit: ""),
            RecordingStat(label: "Distance", value: sim.distanceText, unit: "km"),
            RecordingStat(label: "Vitesse", value: sim.currentSpeedText, unit: "km/h"),
            RecordingStat(label: "Vitesse moy.", value: sim.averageSpeedText, unit: "km/h"),
        ]
    }
}

extension RecordingPrototypeSimulation {
    var pauseBannerText: String? {
        switch phase {
        case .running: nil
        case .paused: "En pause"
        case .autoPaused: "Pause automatique · reprend dès que vous bougez"
        }
    }
}
