#if DEBUG
import MapboxMaps
import SwiftUI

// PROTOTYPE — throwaway (voir SegmentProto.swift).
// Dessiner un Segment : le sport d'abord, puis l'éditeur d'Itinéraire. Ici, chaque tap ajoute un
// point relié en ligne droite et l'altitude est simulée ; dans l'app, ce sera le vrai éditeur
// (tronçons Mapbox Directions, Waypoints déplaçables, annuler/rétablir, D+ de l'ElevationService).

struct ProtoDrawFlow: View {
    let store: ProtoStore
    var onClose: (() -> Void)?

    @State private var sport: ProtoSegmentSport?
    @State private var points: [Coordinate] = []
    @State private var previewed: ProtoPortion?
    @State private var viewport: Viewport = .camera(center: CLLocationCoordinate2D(latitude: 45.8300, longitude: 6.2250), zoom: 13)

    var body: some View {
        NavigationStack {
            Group {
                if let sport {
                    editor(sport)
                } else {
                    sportPicker
                }
            }
            .navigationTitle(sport == nil ? "Dessiner un Segment" : "Nouveau Segment · \(sport!.label)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let onClose {
                    ToolbarItem(placement: .cancellationAction) { Button("Annuler", action: onClose) }
                }
                if sport != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Annuler le dernier point", systemImage: "arrow.uturn.backward") { _ = points.popLast() }
                            .disabled(points.isEmpty)
                    }
                }
            }
            .navigationDestination(item: $previewed) { portion in
                ProtoPreviewView(store: store, portion: portion, sourceTitle: nil, onFinish: {
                    previewed = nil
                    points = []
                    sport = nil
                    onClose?()
                })
            }
        }
    }

    private var sportPicker: some View {
        List {
            Section {
                ForEach(ProtoSegmentSport.allCases) { sport in
                    Button {
                        withAnimation { self.sport = sport }
                    } label: {
                        HStack {
                            Label(sport.label, systemImage: sport.symbol)
                            Spacer()
                            Text(sport == .ride ? "500 m min." : "200 m min.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            } header: {
                Text("Pour quel sport ?")
            } footer: {
                Text("Un Segment n'a qu'un sport : seules les Activités de ce sport y sont classées. Une montée pour le vélo et la course fait deux Segments.")
            }
        }
    }

    private func editor(_ sport: ProtoSegmentSport) -> some View {
        let portion = drawnPortion(sport)
        return Map(viewport: $viewport) {
            if points.count >= 2 {
                PolylineAnnotation(lineCoordinates: points.map(\.locationCoordinate))
                    .lineColor(UIColor(Theme.accent))
                    .lineWidth(5)
                    .lineJoin(.round)
            }
            RouteEndpointsContent(coordinates: points.map(\.locationCoordinate))
            TapInteraction { context in
                points.append(Coordinate(context.coordinate))
                return true
            }
        }
        .mapStyle(.outdoors)
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .top) {
            Text(points.isEmpty ? "Touche la carte pour placer le départ." : "Touche la carte pour prolonger le tracé.")
                .font(.footnote)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Menu {
                        Picker("Sport", selection: Binding(get: { sport }, set: { self.sport = $0 })) {
                            ForEach(ProtoSegmentSport.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Label(sport.label, systemImage: sport.symbol)
                            Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.primary)
                    Spacer()
                    Text("D+ simulé").font(.caption2).foregroundStyle(.secondary)
                }
                if points.count >= 2 {
                    ProtoContinueBarDraw(portion: portion, onContinue: { previewed = $0 })
                }
            }
            .padding(Theme.spacing)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 8)
        }
    }

    /// Tracé dessiné, densifié tous les 50 m, altitude inventée (une montée douce).
    private func drawnPortion(_ sport: ProtoSegmentSport) -> ProtoPortion {
        var coordinates: [Coordinate] = points.first.map { [$0] } ?? []
        var distances: [Double] = points.isEmpty ? [] : [0]
        for (from, to) in zip(points, points.dropFirst()) {
            let length = from.distance(to: to).meters
            let steps = max(Int(length / 50), 1)
            for step in 1...steps {
                let t = Double(step) / Double(steps)
                coordinates.append(Coordinate(
                    latitude: from.latitude + (to.latitude - from.latitude) * t,
                    longitude: from.longitude + (to.longitude - from.longitude) * t
                ))
                distances.append((distances.last ?? 0) + length / Double(steps))
            }
        }
        let altitudes = distances.map { 450 + $0 * 0.055 + sin($0 / 300) * 12 }
        return ProtoPortion(sport: sport, coordinates: coordinates, altitudes: altitudes, distances: distances)
    }
}

private struct ProtoContinueBarDraw: View {
    let portion: ProtoPortion
    let onContinue: (ProtoPortion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProtoPortionStats(portion: portion, compact: true)
            if let problem = portion.problem { problem.banner }
            Button { onContinue(portion) } label: {
                Text("Continuer").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(portion.problem != nil)
        }
    }
}
#endif
