#if DEBUG
import MapboxMaps
import SwiftUI

// PROTOTYPE — throwaway (voir SegmentMapProto.swift).
// Variante B — « Calque Segments » : pas de mode. Un bouton calques (sous « Créer ») allume les
// Segments, choisit le sport et « Favoris seulement ». Les tracés suivent la caméra sans bouton ;
// dézoomé, des bulles regroupent les Segments (toucher = zoomer). Toucher un tracé remplace le
// carrousel d'Itinéraires par l'aperçu du Segment. La pastille « n Segments ici » ouvre la liste.

struct ProtoMapVariantB: View {
    let store: ProtoMapStore

    @State private var isLayerOn = true
    @State private var sport: ProtoMapSport?
    @State private var starredOnly = false
    @State private var viewport: Viewport = .camera(center: SegmentMapProto.me.locationCoordinate, zoom: SegmentMapProto.startZoom)
    @State private var camera = ProtoCamera.initial
    @State private var selectedID: Int?
    @State private var showsList = false
    @State private var bottomHeight: CGFloat = 0

    private var isTooFar: Bool { camera.zoom < SegmentMapProto.minLineZoom }

    private var filtered: [ProtoMapSegment] {
        store.segments
            .filter { sport == nil || $0.sport == sport }
            .filter { !starredOnly || $0.isStarred }
    }

    private var visible: [ProtoMapSegment] {
        filtered.filter { camera.contains($0.start) }
            .sorted { $0.distance(from: camera.center) < $1.distance(from: camera.center) }
    }

    /// Une bulle par case d'un quadrillage d'un quart de l'écran.
    private var clusters: [ProtoCluster] {
        let cell = max(camera.lonSpan / 4, 0.01)
        let groups = Dictionary(grouping: filtered) { segment in
            "\(Int((segment.start.latitude / cell).rounded(.down))):\(Int((segment.start.longitude / cell).rounded(.down)))"
        }
        return groups.map { key, members in
            ProtoCluster(
                id: key,
                center: Coordinate(
                    latitude: members.map(\.start.latitude).reduce(0, +) / Double(members.count),
                    longitude: members.map(\.start.longitude).reduce(0, +) / Double(members.count)
                ),
                count: members.count
            )
        }
    }

    var body: some View {
        ProtoMap(viewport: $viewport, camera: $camera, bottomInset: bottomHeight) {
            if isLayerOn {
                if isTooFar {
                    ForEvery(clusters, id: \.id) { cluster in
                        MapViewAnnotation(coordinate: cluster.center.locationCoordinate) {
                            Button {
                                withViewportAnimation(.easeOut(duration: 0.6)) {
                                    viewport = .camera(center: cluster.center.locationCoordinate, zoom: max(camera.zoom + 2.5, 11.5))
                                }
                            } label: {
                                Text("\(cluster.count)")
                                    .font(.caption.bold()).monospacedDigit()
                                    .foregroundStyle(.white)
                                    .frame(minWidth: 30, minHeight: 30)
                                    .padding(.horizontal, 4)
                                    .background(Color(SegmentMapProto.lineColor), in: Capsule())
                                    .overlay(Capsule().stroke(.white, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                        }
                        .allowOverlap(true)
                    }
                } else {
                    ProtoSegmentLines(segments: visible, focusedID: selectedID) { id in
                        withAnimation(.snappy) { selectedID = id }
                    }
                    // Un point au départ : on repère un Segment même court.
                    ForEvery(visible.filter { $0.id != selectedID }, id: \.id) { segment in
                        MapViewAnnotation(coordinate: segment.start.locationCoordinate) {
                            Circle().fill(.white).frame(width: 10, height: 10)
                                .overlay(Circle().stroke(Color(SegmentMapProto.lineColor), lineWidth: 3))
                                .onTapGesture { withAnimation(.snappy) { selectedID = segment.id } }
                        }
                        .allowOverlap(true)
                    }
                }
            }
        }
        .overlay(alignment: .top) { topControls }
        .overlay(alignment: .bottom) {
            Group {
                if let segment = selectedID.flatMap(store.segment) {
                    ProtoSegmentPreviewB(store: store, segment: segment) { withAnimation(.snappy) { selectedID = nil } }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    ProtoItineraryCarouselMock()
                }
            }
            .padding(.bottom, 8)
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { bottomHeight = $0 }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showsList) { list }
        .onChange(of: selectedID) { _, id in
            guard let segment = id.flatMap(store.segment) else { return }
            withViewportAnimation(.easeOut(duration: 0.5)) { viewport = segment.overview(top: 150) }
        }
    }

    // MARK: Haut

    private var topControls: some View {
        ZStack(alignment: .top) {
            if isLayerOn {
                Button { showsList = true } label: {
                    Label(isTooFar ? "Zoome pour les voir" : "\(visible.count) Segment\(visible.count > 1 ? "s" : "") ici",
                          systemImage: isTooFar ? "plus.magnifyingglass" : "list.bullet")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .glassBackground(in: Capsule(), interactive: true)
                }
                .buttonStyle(.plain)
                .disabled(isTooFar)
                .padding(.top, 4)
            }
            HStack(alignment: .top) {
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    ProtoCreateMenu()
                    layersMenu
                }
            }
        }
        .padding(.horizontal, Theme.spacing)
        .padding(.top, 52)
    }

    private var layersMenu: some View {
        Menu {
            Toggle("Segments", systemImage: "point.topleft.down.to.point.bottomright.curvepath", isOn: $isLayerOn.animation())
            if isLayerOn {
                Picker("Sport", selection: $sport) {
                    Text("Tous les sports").tag(ProtoMapSport?.none)
                    ForEach(ProtoMapSport.allCases) { item in
                        Label(item.label, systemImage: item.symbol).tag(Optional(item))
                    }
                }
                Toggle("Favoris seulement", systemImage: "star", isOn: $starredOnly)
            }
        } label: {
            Image(systemName: "square.3.layers.3d")
                .font(.title3)
                .foregroundStyle(isLayerOn ? Theme.accent : .secondary)
                .frame(width: 48, height: 48)
                .glassBackground(in: Circle(), interactive: true)
        }
        .accessibilityLabel("Calques")
    }

    // MARK: Liste (feuille)

    private var list: some View {
        NavigationStack {
            List(visible) { segment in
                Button {
                    showsList = false
                    withAnimation(.snappy) { selectedID = segment.id }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: segment.sport.symbol).foregroundStyle(Theme.accent).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(segment.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                if segment.isVerified { ProtoVerifiedSeal().font(.caption) }
                            }
                            ProtoSegmentStatsLine(segment: segment).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        ProtoStarButton(store: store, id: segment.id)
                    }
                }
                .tint(.primary)
            }
            .listStyle(.plain)
            .navigationTitle("Segments ici")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ProtoCluster {
    let id: String
    let center: Coordinate
    let count: Int
}

/// Aperçu à la place du carrousel : assez pour décider d'ouvrir la fiche.
private struct ProtoSegmentPreviewB: View {
    let store: ProtoMapStore
    let segment: ProtoMapSegment
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(segment.sport.label, systemImage: segment.sport.symbol)
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Text(segment.name).font(.headline).lineLimit(2)
                        if segment.isVerified { ProtoVerifiedSeal().font(.subheadline) }
                    }
                }
                Spacer(minLength: 0)
                ProtoStarButton(store: store, id: segment.id)
                Button(action: close) {
                    Image(systemName: "xmark").font(.footnote.bold()).frame(width: 32, height: 32)
                        .background(Color(.tertiarySystemFill), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fermer")
            }
            HStack(spacing: Theme.spacing) {
                stat(ProtoMapFormat.distance(segment.meters), "Distance")
                stat(ProtoMapFormat.grade(segment.grade), "Pente moy.")
                stat(segment.category ?? "—", "Catégorie")
                stat(segment.myBest ?? "—", "Mon record")
            }
            NavigationLink(value: ProtoMapRoute.segment(segment.id)) {
                Text("Voir le Segment").font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(Theme.accent, in: Capsule()).foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.spacing)
        .background(Color(.systemBackground), in: .rect(cornerRadius: 20))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 2)
        .padding(.horizontal, Theme.spacing)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}
#endif
