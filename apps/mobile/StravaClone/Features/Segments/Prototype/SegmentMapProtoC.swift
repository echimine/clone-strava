#if DEBUG
import MapboxMaps
import SwiftUI

// PROTOTYPE — throwaway (voir SegmentMapProto.swift).
// Variante C — « Écran Segments » : la Carte reste celle des Itinéraires, avec un bouton « Segments »
// qui ouvre un écran à part (l'écran « Segments » aujourd'hui vide) : petite carte en haut, liste en
// bas. On choisit un sport à la fois, « Autour de toi » (15 km) ou « Favoris », et un tri. Les
// numéros relient la liste aux épingles ; toucher une épingle met la ligne en avant.

struct ProtoMapVariantC: View {
    let store: ProtoMapStore

    @State private var viewport: Viewport = .camera(center: SegmentMapProto.me.locationCoordinate, zoom: SegmentMapProto.startZoom)
    @State private var camera = ProtoCamera.initial

    var body: some View {
        ProtoMap(viewport: $viewport, camera: $camera, bottomInset: 90) {}
            .overlay(alignment: .top) {
                HStack(alignment: .top) {
                    NavigationLink(value: ProtoMapRoute.explore) {
                        Label("Segments", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .glassBackground(in: Capsule(), interactive: true)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                    Spacer()
                    ProtoCreateMenu()
                }
                .padding(.horizontal, Theme.spacing)
                .padding(.top, 52)
            }
            .overlay(alignment: .bottom) { ProtoItineraryCarouselMock().padding(.bottom, 8) }
            .toolbar(.hidden, for: .navigationBar)
    }
}

struct ProtoExploreScreen: View {
    let store: ProtoMapStore

    private enum Scope: String, CaseIterable { case nearby = "Autour de toi", starred = "Favoris" }
    private enum Sort: String, CaseIterable { case near = "Les plus proches", popular = "Les plus courus", steep = "Les plus raides" }

    @State private var scope = Scope.nearby
    @State private var sport = ProtoMapSport.ride
    @State private var sort = Sort.near
    /// Centre de la recherche : toi, puis la carte après « Rechercher ici ».
    @State private var center = SegmentMapProto.me
    @State private var viewport: Viewport = .camera(center: SegmentMapProto.me.locationCoordinate, zoom: 11)
    @State private var camera = ProtoCamera.initial
    @State private var focusedID: Int?
    /// La caméra après le dernier cadrage automatique : seul un geste de l'athlète propose « Rechercher ici ».
    @State private var framedCamera: ProtoCamera?
    @State private var isFraming = false

    private static let radius = 15_000.0

    private var results: [ProtoMapSegment] {
        let base = store.segments.filter { $0.sport == sport }
        let scoped = scope == .nearby ? base.filter { $0.distance(from: center) <= Self.radius } : base.filter(\.isStarred)
        switch sort {
        case .near: return scoped.sorted { $0.distance(from: center) < $1.distance(from: center) }
        case .popular: return scoped.sorted { $0.athletes > $1.athletes }
        case .steep: return scoped.sorted { $0.grade > $1.grade }
        }
    }

    private var movedAway: Bool { framedCamera.map { camera.differs(from: $0) } ?? false }

    var body: some View {
        let results = results
        VStack(spacing: 0) {
            ProtoMap(viewport: $viewport, camera: $camera, ignoresSafeArea: false) {
                ProtoSegmentLines(segments: results, focusedID: focusedID, width: 3) { id in focusedID = id }
                ForEvery(Array(results.enumerated()), id: \.element.id) { index, segment in
                    MapViewAnnotation(coordinate: segment.start.locationCoordinate) {
                        Text("\(index + 1)")
                            .font(.caption2.bold()).monospacedDigit()
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(focusedID == segment.id ? Theme.accent : Color(SegmentMapProto.lineColor), in: Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .onTapGesture { focusedID = segment.id }
                    }
                    .allowOverlap(true)
                    .priority(focusedID == segment.id ? 1 : 0)
                }
            }
            .frame(height: 280)
            .overlay(alignment: .bottom) {
                if movedAway && scope == .nearby {
                    Button {
                        center = camera.center
                        focusedID = nil
                    } label: {
                        Label("Rechercher dans cette zone", systemImage: "arrow.clockwise")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .glassBackground(in: Capsule(), interactive: true)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 10)
                }
            }
            controls
            List {
                Section {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, segment in
                        NavigationLink(value: ProtoMapRoute.segment(segment.id)) {
                            ProtoExploreRow(store: store, segment: segment, number: index + 1, away: segment.distance(from: SegmentMapProto.me))
                        }
                        .listRowBackground(focusedID == segment.id ? Theme.accent.opacity(0.12) : nil)
                    }
                } footer: {
                    if results.isEmpty {
                        Text(scope == .starred ? "Touche l'étoile d'un Segment pour le retrouver ici." : "Aucun Segment de ce sport à moins de 15 km.")
                    }
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("Segments")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: focusedID) { _, id in
            guard let segment = id.flatMap(store.segment) else { return }
            isFraming = true
            withViewportAnimation(.easeOut(duration: 0.5)) { viewport = segment.overview(top: 30, bottom: 30) }
        }
        .onChange(of: camera) {
            if isFraming || framedCamera == nil { framedCamera = camera; isFraming = false }
        }
        // Sport, portée ou tri changés : la carte cadre toute la liste.
        .onChange(of: results.map(\.id), initial: true) {
            let coordinates = results.flatMap(\.line)
            guard coordinates.count >= 2 else { return }
            isFraming = true
            withViewportAnimation(.easeOut(duration: 0.5)) {
                viewport = .overview(geometry: MultiPoint(coordinates), geometryPadding: EdgeInsets(top: 30, leading: 30, bottom: 30, trailing: 30))
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Picker("Portée", selection: $scope) {
                ForEach(Scope.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            HStack {
                Menu {
                    Picker("Sport", selection: $sport) {
                        ForEach(ProtoMapSport.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                    }
                } label: {
                    Label(sport.label, systemImage: sport.symbol).font(.footnote.weight(.semibold))
                }
                Menu {
                    Picker("Tri", selection: $sort) {
                        ForEach(Sort.allCases, id: \.self) { Text($0.rawValue) }
                    }
                } label: {
                    Label(sort.rawValue, systemImage: "arrow.up.arrow.down").font(.footnote.weight(.semibold))
                }
                Spacer()
                Text(center == SegmentMapProto.me || scope == .starred ? "Autour de toi" : "Zone de la carte")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Theme.spacing)
        .padding(.vertical, 10)
    }
}

private struct ProtoExploreRow: View {
    let store: ProtoMapStore
    let segment: ProtoMapSegment
    let number: Int
    let away: Double

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.caption.bold()).monospacedDigit()
                .frame(width: 24, height: 24)
                .background(Color(.tertiarySystemFill), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(segment.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if segment.isVerified { ProtoVerifiedSeal().font(.caption) }
                }
                ProtoSegmentStatsLine(segment: segment).font(.caption)
                HStack(spacing: 8) {
                    Text("à \(ProtoMapFormat.away(away))")
                    Text(ProtoMapFormat.athletes(segment.athletes))
                    if let mine = segment.myBest { Text("Mon record \(mine)") }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            ProtoStarButton(store: store, id: segment.id)
        }
    }
}
#endif
