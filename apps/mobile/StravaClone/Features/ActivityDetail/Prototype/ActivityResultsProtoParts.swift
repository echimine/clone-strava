#if DEBUG
import MapboxMaps
import SwiftUI

// PROTOTYPE — throwaway (voir ActivityResultsProto.swift). Briques communes aux trois variantes.

// MARK: - Carte de l'Activité avec les badges des Segments

struct ProtoResultsMap: View {
    let state: ProtoResultsState
    @State private var viewport: Viewport = .idle

    var body: some View {
        let line = state.route.map(\.locationCoordinate)
        Map(viewport: $viewport) {
            PolylineAnnotation(lineCoordinates: line)
                .lineColor(UIColor(Theme.accent)).lineWidth(4).lineJoin(.round)
            RouteEndpointsContent(coordinates: line)
            if state.variant != "A" {
                ForEvery(state.segments) { segment in
                    PolylineAnnotation(lineCoordinates: Array(line[segment.range]))
                        .lineColor(UIColor(state.selected == segment.id ? .black : Color(red: 0.55, green: 0.15, blue: 0)))
                        .lineWidth(state.selected == segment.id ? 7 : 5).lineJoin(.round)
                }
            }
            ForEvery(Array(state.segments.enumerated()), id: \.element.id) { index, segment in
                MapViewAnnotation(coordinate: line[segment.range.lowerBound]) {
                    badge(segment, number: index + 1)
                        .onTapGesture { tap(segment) }
                }
                .allowOverlap(true)
                .variableAnchors([ViewAnnotationAnchorConfig(anchor: .bottom)])
            }
        }
        .mapStyle(.outdoors)
        .gestureOptions(GestureOptions(rotateEnabled: false, pitchEnabled: false))
        .frame(height: 330)
        .onAppear { viewport = overview(line) }
        .onChange(of: state.route.count) { viewport = overview(state.route.map(\.locationCoordinate)) }
        .onChange(of: state.selected) {
            let target = state.segments.first { $0.id == state.selected }.map { Array(line[$0.range]) } ?? line
            withViewportAnimation(.easeInOut(duration: 0.6)) { viewport = overview(target) }
        }
        .overlay(alignment: .bottomLeading) {
            if state.isMatching {
                HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("Recherche des Segments…") }
                    .font(.caption2).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule()).padding(8)
            }
        }
    }

    private func overview(_ line: [CLLocationCoordinate2D]) -> Viewport {
        .overview(geometry: LineString(line), geometryPadding: EdgeInsets(top: 48, leading: 32, bottom: 48, trailing: 32))
    }

    private func tap(_ segment: ProtoSegmentResult) {
        guard state.variant != "A" else { return }
        withAnimation {
            state.selected = state.selected == segment.id ? nil : segment.id
            if state.variant == "C" { state.tab = 1 }
        }
    }

    /// A : Médaille et nom (rien sans Médaille) ; B : numéro dans la liste ; C : Médaille seule, point gris sinon.
    @ViewBuilder private func badge(_ segment: ProtoSegmentResult, number: Int) -> some View {
        switch state.variant {
        case "A":
            if let medal = segment.medal {
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        ProtoMedal(place: medal, size: 18)
                        Text(segment.name).font(.caption2.weight(.semibold)).lineLimit(1)
                    }
                    .padding(.leading, 3).padding(.trailing, 8).padding(.vertical, 3)
                    .background(.background, in: Capsule())
                    .shadow(radius: 2)
                    Rectangle().fill(.primary).frame(width: 2, height: 8)
                }
                .frame(maxWidth: 190)
            }
        case "B":
            ZStack {
                Circle().fill(state.selected == segment.id ? Color.black : Color(red: 0.55, green: 0.15, blue: 0))
                Text("\(number)").font(.caption.weight(.bold)).foregroundStyle(.white)
            }
            .frame(width: 24, height: 24)
            .overlay(Circle().stroke(segment.medal.map(ProtoMedalColor.color) ?? .white, lineWidth: 3))
            .shadow(radius: 2)
        default:
            if let medal = segment.medal {
                ProtoMedal(place: medal, size: state.selected == segment.id ? 30 : 24)
                    .overlay(Circle().stroke(.white, lineWidth: 2)).shadow(radius: 2)
            } else {
                Circle().fill(Color(.systemGray)).frame(width: 12, height: 12)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
            }
        }
    }
}

enum ProtoMedalColor {
    static func color(_ place: Int) -> Color {
        [Color(red: 0.93, green: 0.73, blue: 0.13), Color(white: 0.66), Color(red: 0.78, green: 0.5, blue: 0.26)][place - 1]
    }
}

// MARK: - Lignes

/// Médaille, ou un cercle vide sans Médaille : les lignes restent alignées.
struct ProtoMedalSlot: View {
    let medal: Int?
    var size: CGFloat = 26
    var body: some View {
        if let medal { ProtoMedal(place: medal, size: size) } else {
            Circle().stroke(Color(.systemGray4), lineWidth: 1.5).frame(width: size, height: size)
        }
    }
}

struct ProtoSegmentResultRow: View {
    let state: ProtoResultsState
    let segment: ProtoSegmentResult
    var number: Int?
    /// C : toucher met le Segment en avant sur la carte au lieu d'ouvrir la fiche.
    var onSelect: (() -> Void)?

    var body: some View {
        if let onSelect {
            Button(action: onSelect) { content }.buttonStyle(.plain)
        } else {
            NavigationLink(value: ProtoMapRoute.segment(segment.id)) { content }.buttonStyle(.plain)
        }
    }

    private var content: some View {
            HStack(spacing: 12) {
                if let number {
                    Text("\(number)").font(.caption.weight(.bold)).foregroundStyle(.white)
                        .frame(width: 22, height: 22).background(Color(red: 0.55, green: 0.15, blue: 0), in: Circle())
                }
                ProtoMedalSlot(medal: segment.medal)
                VStack(alignment: .leading, spacing: 2) {
                    Text(segment.name).font(.subheadline.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(ProtoFicheData.time(segment.seconds)).font(.subheadline.weight(.semibold)).monospacedDigit()
                    Text(state.showsRank ? ProtoMedalText.rank(segment.rank, of: segment.athletes) : "Hors Classement")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Image(systemName: onSelect == nil ? "chevron.right" : "scope").font(.caption).foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
    }

    private var subtitle: String {
        let facts = "\(ProtoMapFormat.distance(segment.meters)) · \(ProtoMapFormat.grade(segment.grade))"
        guard let label = ProtoMedalText.label(segment.medal) else { return facts }
        return "\(label)\(segment.isFirstPass ? " · 1er passage" : "") · \(facts)"
    }
}

struct ProtoRecordResultRow: View {
    let state: ProtoResultsState
    let record: ProtoRecordResult

    var body: some View {
        HStack(spacing: 12) {
            ProtoMedalSlot(medal: record.medal)
            VStack(alignment: .leading, spacing: 2) {
                Text("Record \(record.label)").font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(ProtoFicheData.time(record.seconds)).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
        .contentShape(.rect)
        .contextMenu {
            if state.isMine {
                Button("Retirer ce temps de mes Records", systemImage: "minus.circle", role: .destructive) { state.remove(record) }
            }
        }
    }

    private var subtitle: String {
        if record.isFirstTime { return "Meilleur temps · 1re fois sur \(record.label)" }
        return ProtoMedalText.label(record.medal) ?? "Pas dans les 3 meilleurs temps"
    }
}

struct ProtoMatchingRow: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Recherche des Segments de cette Activité…").font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

/// Activité non publique : ses Efforts ne comptent pas au Classement (#228), les Médailles restent.
struct ProtoPrivacyNote: View {
    let state: ProtoResultsState
    var body: some View {
        if state.visibility != .public, state.sport == .ride {
            Label(state.visibility == .private
                  ? "Activité privée : ses Efforts ne comptent pas au Classement. Les Médailles restent."
                  : "Activité visible des abonnés : ses Efforts ne comptent pas au Classement. Les Médailles restent.",
                  systemImage: "lock")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Tous les résultats (écran poussé, variante A)

struct ProtoAllResultsScreen: View {
    let state: ProtoResultsState

    var body: some View {
        List {
            if state.sport == .ride {
                Section {
                    if state.isMatching { ProtoMatchingRow() }
                    ForEach(state.segments) { ProtoSegmentResultRow(state: state, segment: $0) }
                } header: {
                    Text("Segments (\(state.segments.count))")
                } footer: {
                    ProtoPrivacyNote(state: state)
                }
            }
            Section {
                ForEach(state.records) { ProtoRecordResultRow(state: state, record: $0) }
            } header: {
                Text(state.sport == .pool ? "Records · piscine, bassin de 25 m" : "Records (\(state.records.count))")
            } footer: {
                if state.isMine { Text("Appui long sur un temps pour le retirer de tes Records.") }
            }
        }
        .navigationTitle("Résultats")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Les trois compteurs (Médailles, Segments, Records).
struct ProtoCounters: View {
    let state: ProtoResultsState
    var tiles = false

    var body: some View {
        HStack(spacing: tiles ? 8 : 0) {
            counter("\(state.medalCount)", "Médailles", "medal.fill")
            if state.sport == .ride {
                if !tiles { Divider().frame(height: 32) }
                counter(state.isMatching ? "…" : "\(state.segments.count)", "Segments", "point.topleft.down.to.point.bottomright.curvepath")
            }
            if !tiles { Divider().frame(height: 32) }
            counter("\(state.records.count)", "Records", "stopwatch")
        }
    }

    private func counter(_ value: String, _ label: String, _ symbol: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.bold)).monospacedDigit()
            Label(label, systemImage: symbol).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, tiles ? 10 : 0)
        .background(tiles ? Color(.secondarySystemGroupedBackground) : .clear, in: .rect(cornerRadius: 14))
    }
}
#endif
