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
                .allowOverlap(state.variant != "A")
                .variableAnchors([state.variant == "A"
                    ? ViewAnnotationAnchorConfig(anchor: .left, offsetX: -14)
                    : ViewAnnotationAnchorConfig(anchor: .bottom)])
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
            // Comme Strava : la médaille sur la trace, et à droite « Record personnel » puis le nom, sans fond.
            if let medal = segment.medal {
                HStack(spacing: 4) {
                    ProtoMedal(place: medal, size: 28)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(ProtoMedalText.label(medal) ?? "")
                        Text(segment.name).lineLimit(2)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(white: 0.15))
                    .shadow(color: .white, radius: 1).shadow(color: .white, radius: 1).shadow(color: .white, radius: 2)
                }
                .frame(width: 190, alignment: .leading)
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
        ProtoMedal.gradients[place - 1][1]
    }
}

// MARK: - Lignes

/// Médaille, ou un vide de même largeur sans Médaille : les lignes restent alignées.
struct ProtoMedalSlot: View {
    let medal: Int?
    var size: CGFloat = 30
    var body: some View {
        if let medal { ProtoMedal(place: medal, size: size) } else {
            Color.clear.frame(width: size, height: size)
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
                  ? "Activité privée : ses Efforts ne comptent pas au Classement. Les médailles restent."
                  : "Activité visible des abonnés : ses Efforts ne comptent pas au Classement. Les médailles restent.",
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
            Section {
                ForEach(state.records) { ProtoStravaRecordRow(state: state, record: $0) }
            } header: {
                Text(state.sport == .pool ? "Meilleurs efforts · piscine, bassin de 25 m" : "Meilleurs efforts")
            } footer: {
                if state.isMine { Text("Appui long sur un temps pour le retirer de tes meilleurs efforts.") }
            }
            if state.sport == .ride {
                Section {
                    if state.isMatching { ProtoMatchingRow() }
                    ForEach(state.segments) { ProtoStravaSegmentRow(state: state, segment: $0) }
                } header: {
                    Text("Segments")
                } footer: {
                    ProtoPrivacyNote(state: state)
                }
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
            counter("\(state.records.count)", "Meilleurs efforts", "stopwatch")
            if state.sport == .ride {
                if !tiles { Divider().frame(height: 32) }
                counter(state.isMatching ? "…" : "\(state.segments.count)", "Segments", "point.topleft.down.to.point.bottomright.curvepath")
            }
            if !tiles { Divider().frame(height: 32) }
            counter("\(state.medalCount)", "Performances", "medal.fill")
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

#if DEBUG
// MARK: - A, comme Strava

/// Une ligne de « Résultats » : médaille, titre, temps et allure (vitesse), puis la phrase de la médaille.
struct ProtoStravaRow: View {
    let state: ProtoResultsState
    let title: String
    let meters: Double
    let seconds: Int
    let medal: Int?
    var showsDistance = false
    var note: String?

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ProtoMedalSlot(medal: medal)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body).multilineTextAlignment(.leading)
                HStack(spacing: 14) {
                    if showsDistance { Text(ProtoMapFormat.distance(meters)) }
                    Text(ProtoFicheData.time(seconds))
                    Text(pace)
                }
                .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                if let note { Text(note).font(.subheadline) }
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
    }

    /// Vélo : km/h ; natation : /100 m ; sinon /km.
    private var pace: String {
        switch state.sport {
        case .ride:
            return "\((meters / Double(seconds) * 3.6).formatted(.number.precision(.fractionLength(1)).locale(ActivityFormatters.locale))) km/h"
        case .pool:
            let per100 = Int((Double(seconds) / meters * 100).rounded())
            return "\(ProtoFicheData.time(per100)) /100 m"
        }
    }
}

struct ProtoStravaSegmentRow: View {
    let state: ProtoResultsState
    let segment: ProtoSegmentResult

    var body: some View {
        NavigationLink(value: ProtoMapRoute.segment(segment.id)) {
            ProtoStravaRow(state: state, title: segment.name, meters: segment.meters, seconds: segment.seconds,
                           medal: segment.medal, showsDistance: true,
                           note: segment.medal.flatMap(ProtoMedalText.label).map { segment.isFirstPass ? "\($0) · 1er passage" : $0 })
        }
        .buttonStyle(.plain)
    }
}

struct ProtoStravaRecordRow: View {
    let state: ProtoResultsState
    let record: ProtoRecordResult

    var body: some View {
        ProtoStravaRow(state: state, title: record.label.uppercased(), meters: record.meters, seconds: record.seconds,
                       medal: record.medal, note: ProtoMedalText.bestEffort(record.medal))
            .contextMenu {
                if state.isMine {
                    Button("Retirer ce temps de mes meilleurs efforts", systemImage: "minus.circle", role: .destructive) { state.remove(record) }
                }
            }
    }
}
#endif
