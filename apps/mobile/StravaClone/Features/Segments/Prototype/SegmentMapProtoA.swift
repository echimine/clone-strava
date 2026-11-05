#if DEBUG
import MapboxMaps
import SwiftUI

// PROTOTYPE — throwaway (voir SegmentMapProto.swift).
// Variante A — « Itinéraires | Segments » : la Carte a deux modes. En mode Segments, des puces de
// sport et Favoris, les tracés de la zone cherchée, un carrousel de cartes comme les Itinéraires.
// La zone ne suit pas la caméra : quand on bouge, « Rechercher dans cette zone » (comme Strava).
// Dézoomé (< 10,5) : plus de tracés, « Zoome pour voir les Segments ».

struct ProtoMapVariantA: View {
    let store: ProtoMapStore

    private enum Mode: String, CaseIterable { case itineraries = "Itinéraires", segments = "Segments" }

    @State private var mode = Mode.segments
    @State private var sport: ProtoMapSport?
    @State private var starredOnly = false
    @State private var viewport: Viewport = .camera(center: SegmentMapProto.me.locationCoordinate, zoom: SegmentMapProto.startZoom)
    @State private var camera = ProtoCamera.initial
    @State private var searchedArea = ProtoCamera.initial
    @State private var focusedID: Int?
    @State private var bottomHeight: CGFloat = 0

    private var isTooFar: Bool { camera.zoom < SegmentMapProto.minLineZoom }

    private var results: [ProtoMapSegment] {
        store.segments
            .filter { searchedArea.contains($0.start) }
            .filter { sport == nil || $0.sport == sport }
            .filter { !starredOnly || $0.isStarred }
            .sorted { $0.distance(from: searchedArea.center) < $1.distance(from: searchedArea.center) }
    }

    var body: some View {
        ProtoMap(viewport: $viewport, camera: $camera, bottomInset: bottomHeight) {
            if mode == .segments && !isTooFar {
                ProtoSegmentLines(segments: results, focusedID: focusedID) { id in
                    withAnimation(.snappy) { focusedID = id }
                }
            }
        }
        .overlay(alignment: .top) { topControls }
        .overlay(alignment: .bottom) {
            Group {
                if mode == .segments { carousel } else { ProtoItineraryCarouselMock() }
            }
            .padding(.bottom, 8)
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { bottomHeight = $0 }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: focusedID) { _, id in
            guard let segment = id.flatMap(store.segment) else { return }
            withViewportAnimation(.easeOut(duration: 0.5)) { viewport = segment.overview(top: 190) }
        }
        .onChange(of: camera) { old, new in
            // Le premier arrêt (taille réelle de la carte) fixe la zone de départ.
            if old == .initial { searchedArea = new }
        }
    }

    // MARK: Haut

    private var topControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Picker("Mode", selection: $mode.animation()) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .padding(4)
                .glassBackground(in: Capsule())
                Spacer()
                ProtoCreateMenu()
            }
            if mode == .segments {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ProtoChip(title: "Tous", isOn: sport == nil) { sport = nil }
                        ForEach(ProtoMapSport.allCases) { item in
                            ProtoChip(title: item.short, symbol: item.symbol, isOn: sport == item) { sport = item }
                        }
                        ProtoChip(title: "Favoris", symbol: "star.fill", isOn: starredOnly) { starredOnly.toggle() }
                    }
                    .padding(.horizontal, Theme.spacing)
                }
                .scrollIndicators(.hidden)
                .padding(.horizontal, -Theme.spacing)
                Group {
                    if isTooFar {
                        Label("Zoome pour voir les Segments", systemImage: "plus.magnifyingglass")
                    } else if camera.differs(from: searchedArea) {
                        Button {
                            withAnimation { searchedArea = camera; focusedID = nil }
                        } label: {
                            Label("Rechercher dans cette zone", systemImage: "arrow.clockwise")
                        }
                    }
                }
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 9)
                .glassBackground(in: Capsule(), interactive: true)
                .frame(maxWidth: .infinity)
                .opacity(isTooFar || camera.differs(from: searchedArea) ? 1 : 0)
            }
        }
        .padding(.horizontal, Theme.spacing)
        .padding(.top, 52)
    }

    // MARK: Bas

    @ViewBuilder private var carousel: some View {
        if isTooFar {
            EmptyView()
        } else if results.isEmpty {
            Label(starredOnly ? "Aucun Segment favori dans cette zone." : "Aucun Segment dans cette zone. Crée le premier !",
                  systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.subheadline).foregroundStyle(.secondary)
                .padding(Theme.spacing)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassBackground(in: .rect(cornerRadius: 20))
                .padding(.horizontal, Theme.spacing)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(results.count) Segment\(results.count > 1 ? "s" : "") dans cette zone")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .glassBackground(in: Capsule())
                    .padding(.horizontal, Theme.spacing)
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(results) { segment in
                            NavigationLink(value: ProtoMapRoute.segment(segment.id)) {
                                ProtoSegmentCardA(store: store, segment: segment, isFocused: focusedID == segment.id)
                            }
                            .buttonStyle(.plain)
                            .containerRelativeFrame(.horizontal) { width, _ in
                                width - 2 * Theme.spacing - (results.count > 1 ? 24 : 0)
                            }
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, Theme.spacing, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $focusedID, anchor: .center)
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .sensoryFeedback(.selection, trigger: focusedID)
            }
        }
    }
}

private struct ProtoSegmentCardA: View {
    let store: ProtoMapStore
    let segment: ProtoMapSegment
    let isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: segment.sport.symbol).foregroundStyle(Theme.accent)
                Text(segment.name).font(.headline).lineLimit(1)
                if segment.isVerified { ProtoVerifiedSeal().font(.subheadline) }
                Spacer(minLength: 0)
                ProtoStarButton(store: store, id: segment.id)
            }
            ProtoSegmentStatsLine(segment: segment).font(.subheadline.weight(.semibold))
            HStack {
                Text(ProtoMapFormat.athletes(segment.athletes))
                Spacer()
                if let mine = segment.myBest {
                    Label("Mon record \(mine)", systemImage: "stopwatch")
                } else {
                    Text("1er : \(segment.leaderTime)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(Theme.spacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.accent, lineWidth: isFocused ? 2 : 0))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .contentShape(.rect(cornerRadius: 20))
    }
}
#endif
