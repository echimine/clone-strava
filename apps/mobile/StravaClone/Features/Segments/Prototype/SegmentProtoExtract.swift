#if DEBUG
import MapboxMaps
import SwiftUI

// PROTOTYPE — throwaway (voir SegmentProto.swift).
// Extraire un Segment d'une de ses Activités : trois façons de choisir le début et la fin.
// A : carte en haut, double curseur sur le profil d'altitude.
// B : carte plein écran, drapeaux de départ et d'arrivée déplacés sur la trace.
// C : deux étapes, un curseur pour le départ puis un pour l'arrivée, carte zoomée sur le point.

enum ProtoExtractVariants {
    static let all = [
        ProtoVariant(key: "A", name: "Curseurs sur le profil"),
        ProtoVariant(key: "B", name: "Drapeaux sur la carte"),
        ProtoVariant(key: "C", name: "Départ puis arrivée"),
    ]
}

struct ProtoExtractFlow: View {
    let store: ProtoStore
    var showsSwitcher = true
    var onClose: (() -> Void)?
    @AppStorage("protoExtract") private var variant = "A"
    @State private var previewed: ProtoPortion?

    var body: some View {
        NavigationStack {
            Group {
                switch variant {
                case "B": ProtoExtractB(track: .sample, onContinue: { previewed = $0 })
                case "C": ProtoExtractC(track: .sample, onContinue: { previewed = $0 })
                default: ProtoExtractA(track: .sample, onContinue: { previewed = $0 })
                }
            }
            .id(variant)
            .navigationTitle("Créer un Segment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let onClose {
                    ToolbarItem(placement: .cancellationAction) { Button("Annuler", action: onClose) }
                }
            }
            .navigationDestination(item: $previewed) { portion in
                ProtoPreviewView(store: store, portion: portion, sourceTitle: ProtoTrack.sample.title, onFinish: { onClose?() ; previewed = nil })
            }
            .safeAreaInset(edge: .top) {
                if showsSwitcher && previewed == nil {
                    ProtoSwitcher(title: "Extraire", variants: ProtoExtractVariants.all, current: $variant)
                }
            }
        }
    }
}

extension ProtoPortion: Identifiable, Hashable {
    var id: String { "\(coordinates.first?.latitude ?? 0)-\(coordinates.last?.latitude ?? 0)-\(meters)" }
    static func == (lhs: ProtoPortion, rhs: ProtoPortion) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// En-tête commun : de quelle Activité on extrait.
private struct ProtoSourceHeader: View {
    let track: ProtoTrack

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: track.sport.symbol).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 0) {
                Text(track.title).font(.subheadline.weight(.semibold))
                Text("Sortie vélo · \(ProtoFormat.distance(track.totalMeters)) · hier").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

/// Bas d'écran commun : stats en direct, garde-fou, bouton.
private struct ProtoContinueBar: View {
    let portion: ProtoPortion
    let onContinue: (ProtoPortion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProtoPortionStats(portion: portion, compact: true)
            if let problem = portion.problem {
                problem.banner
            }
            Button {
                onContinue(portion)
            } label: {
                Text("Continuer").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(portion.problem != nil)
        }
        .animation(.default, value: portion.problem)
    }
}

// MARK: - A : curseurs sur le profil

struct ProtoExtractA: View {
    let track: ProtoTrack
    let onContinue: (ProtoPortion) -> Void
    @State private var range: ClosedRange<Int>
    @State private var viewport: Viewport

    init(track: ProtoTrack, onContinue: @escaping (ProtoPortion) -> Void) {
        self.track = track
        self.onContinue = onContinue
        _range = State(initialValue: track.firstAllowed...(track.points.count - 1))
        _viewport = State(initialValue: track.overview())
    }

    var body: some View {
        VStack(spacing: 0) {
            Map(viewport: $viewport) {
                ProtoTrackContent(track: track, range: range)
                RouteEndpointsContent(coordinates: [track.coordinates[range.lowerBound], track.coordinates[range.upperBound]])
            }
            .mapStyle(.outdoors)
            .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 12) {
                ProtoSourceHeader(track: track)
                Text("Glisse les drapeaux sur le profil pour choisir le début et la fin.")
                    .font(.footnote).foregroundStyle(.secondary)
                ProtoRangeProfile(track: track, range: $range, isInteractive: true)
                    .frame(height: 150)
                    .padding(.bottom, 8)
                ProtoContinueBar(portion: track.portion(range), onContinue: onContinue)
            }
            .padding(Theme.spacing)
            .background(Color(.systemBackground))
        }
    }
}

// MARK: - B : drapeaux sur la carte

struct ProtoExtractB: View {
    let track: ProtoTrack
    let onContinue: (ProtoPortion) -> Void
    @State private var range: ClosedRange<Int>
    @State private var viewport: Viewport
    @State private var dragged: RouteEndpoint?

    init(track: ProtoTrack, onContinue: @escaping (ProtoPortion) -> Void) {
        self.track = track
        self.onContinue = onContinue
        let start = track.index(atMeters: 12_300)
        _range = State(initialValue: start...(track.points.count - 1))
        _viewport = State(initialValue: track.overview(padding: SwiftUI.EdgeInsets(top: 80, leading: 40, bottom: 330, trailing: 40)))
    }

    var body: some View {
        MapReader { proxy in
            Map(viewport: $viewport) {
                ProtoTrackContent(track: track, range: range)
                flag(.start, index: range.lowerBound, proxy: proxy)
                flag(.finish, index: range.upperBound, proxy: proxy)
            }
            .mapStyle(.outdoors)
            .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Text(dragged == nil ? "Fais glisser les drapeaux le long de ta trace." : "Relâche pour placer le \(dragged == .start ? "départ" : "l'arrivée").")
                .font(.footnote)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(.top, 56)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                ProtoSourceHeader(track: track)
                ProtoRangeProfile(track: track, range: $range)
                    .frame(height: 70)
                    .chartXAxis(.hidden).chartYAxis(.hidden)
                ProtoContinueBar(portion: track.portion(range), onContinue: onContinue)
            }
            .padding(Theme.spacing)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 8)
        }
    }

    private func flag(_ endpoint: RouteEndpoint, index: Int, proxy: MapProxy) -> MapViewAnnotation {
        MapViewAnnotation(coordinate: track.coordinates[index]) {
            Image(systemName: endpoint.symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(endpoint.color, in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: 3))
                .shadow(radius: dragged == endpoint ? 6 : 2)
                .scaleEffect(dragged == endpoint ? 1.25 : 1)
                .gesture(
                    DragGesture(minimumDistance: 2, coordinateSpace: .global)
                        .onChanged { value in
                            dragged = endpoint
                            guard let map = proxy.map else { return }
                            // Le doigt au-dessus du drapeau, pour voir la trace dessous.
                            let point = CGPoint(x: value.location.x, y: value.location.y - 40)
                            let snapped = max(track.nearestIndex(to: Coordinate(map.coordinate(for: point))), track.firstAllowed)
                            if endpoint == .start {
                                range = min(snapped, range.upperBound - 1)...range.upperBound
                            } else {
                                range = range.lowerBound...max(snapped, range.lowerBound + 1)
                            }
                        }
                        .onEnded { _ in dragged = nil }
                )
        }
        .allowOverlap(true)
        .priority(endpoint == .finish ? 2 : 1)
    }
}

// MARK: - C : départ puis arrivée

struct ProtoExtractC: View {
    let track: ProtoTrack
    let onContinue: (ProtoPortion) -> Void
    @State private var step: RouteEndpoint = .start
    @State private var start: Int
    @State private var finish: Int
    @State private var viewport: Viewport

    init(track: ProtoTrack, onContinue: @escaping (ProtoPortion) -> Void) {
        self.track = track
        self.onContinue = onContinue
        let start = track.index(atMeters: 12_300)
        _start = State(initialValue: start)
        _finish = State(initialValue: track.points.count - 1)
        _viewport = State(initialValue: .camera(center: track.coordinates[start], zoom: 14.5))
    }

    private var current: Int { step == .start ? start : finish }

    var body: some View {
        VStack(spacing: 0) {
            Map(viewport: $viewport) {
                ProtoTrackContent(track: track, range: step == .start ? start...(start + 1) : start...max(finish, start + 1))
                if step == .finish {
                    RouteEndpointsContent(coordinates: [track.coordinates[start], track.coordinates[start]])
                }
                MapViewAnnotation(coordinate: track.coordinates[current]) {
                    Image(systemName: step.symbol)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(step.color, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 3))
                        .shadow(radius: 3)
                }
                .allowOverlap(true)
            }
            .mapStyle(.outdoors)
            .overlay(alignment: .topLeading) {
                Text("Étape \(step == .start ? 1 : 2) sur 2")
                    .font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 56).padding(.leading, Theme.spacing)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(step == .start ? "Où commence le Segment ?" : "Où finit-il ?")
                    .font(.title3.bold())
                HStack {
                    Text("Au km \((track.cumulative[current] / 1_000).formatted(.number.precision(.fractionLength(2)).locale(ActivityFormatters.locale)))").font(.subheadline.monospacedDigit())
                    Text("· \(ActivityFormatters.elevation(track.points[current].altitude)) d'altitude")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                }
                HStack(spacing: 8) {
                    nudge(-1)
                    Slider(value: sliderValue, in: sliderBounds, step: 1)
                        .tint(step.color)
                    nudge(1)
                }
                if step == .finish {
                    ProtoContinueBar(portion: track.portion(start...finish), onContinue: onContinue)
                    Button("Changer le départ") { withAnimation { step = .start; follow(start) } }
                        .font(.footnote)
                        .frame(maxWidth: .infinity)
                } else {
                    if track.gapIndices.contains(start + 1) || track.gapIndices.contains(start) {
                        ProtoProblem.pause.banner
                    }
                    Button {
                        withAnimation {
                            finish = max(finish, start + 1)
                            step = .finish
                            follow(finish)
                        }
                    } label: {
                        Text("Suivant : l'arrivée").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(Theme.spacing)
            .background(Color(.systemBackground))
        }
    }

    private var sliderBounds: ClosedRange<Double> {
        step == .start
            ? Double(track.firstAllowed)...Double(track.points.count - 2)
            : Double(start + 1)...Double(track.points.count - 1)
    }

    private var sliderValue: Binding<Double> {
        Binding(
            get: { Double(current) },
            set: { value in
                let index = Int(value)
                if step == .start { start = index } else { finish = index }
                follow(index)
            }
        )
    }

    /// Un point de plus ou de moins (~80 m) : le curseur est trop grossier sur 24 km.
    private func nudge(_ delta: Int) -> some View {
        Button {
            let bounds = sliderBounds
            let next = min(max(Double(current + delta), bounds.lowerBound), bounds.upperBound)
            sliderValue.wrappedValue = next
        } label: {
            Image(systemName: delta < 0 ? "minus" : "plus")
                .font(.headline)
                .frame(width: 36, height: 36)
                .background(Color(.tertiarySystemFill), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func follow(_ index: Int) {
        withViewportAnimation(.easeOut(duration: 0.25)) {
            viewport = .camera(center: track.coordinates[index], zoom: 14.5)
        }
    }
}
#endif
