#if DEBUG
import CoreLocation
import MapboxMaps
import SwiftUI

// PROTOTYPE — throwaway. Ticket « Prototype : les Segments sur la carte » (#237), carte
// « Segments et Records dans l'app » (#223). Branche prototype/segment-map, jamais fusionnée.
//
// Lancement : argument `-SegmentMapPrototype` (Edit Scheme > Run > Arguments), à la place de l'app.
// Options : `-protoVariant A|B|C`, `-protoExplore YES` (C, ouvre l'écran Segments). La pastille violette en haut cycle les variantes :
//   A — Itinéraires | Segments : un mode de la Carte, puces de sport, carrousel, « Rechercher ici ».
//   B — Calque Segments : tracés toujours sur la carte, regroupés quand on dézoome, aperçu au toucher.
//   C — Écran Segments : un bouton de la Carte ouvre une carte + liste « Autour de toi ».
// Tu es au Pâquier, à Annecy (position simulée). Tracés réels par Mapbox Directions au lancement ;
// les Segments loin d'Annecy sont inventés (lignes droites) pour voir le dézoom. Rien n'est envoyé.

enum SegmentMapProto {
    static let launchArgument = "-SegmentMapPrototype"
    static let me = Coordinate(latitude: 45.9015, longitude: 6.1335)
    static let startZoom = 12.5
    /// Sous ce zoom, on ne dessine plus les tracés (trop nombreux à l'échelle du monde).
    static let minLineZoom = 10.5
    static let lineColor = UIColor(red: 0.18, green: 0.2, blue: 0.3, alpha: 0.85)
}

// MARK: - Sport

enum ProtoMapSport: String, CaseIterable, Identifiable {
    case ride, run, walk, hike
    var id: String { rawValue }

    var sportType: SportType {
        switch self {
        case .run: .run
        case .ride: .ride
        case .walk: .walk
        case .hike: .hike
        }
    }

    var label: String { ActivityFormatters.sportLabel(sportType) }
    var symbol: String { ActivityFormatters.sportSymbol(sportType) }
    var short: String {
        switch self {
        case .ride: "Vélo"
        case .run: "Course"
        case .walk: "Marche"
        case .hike: "Rando"
        }
    }

    var routingProfile: String { self == .ride ? "cycling" : "walking" }
}

// MARK: - Segment

struct ProtoMapSegment: Identifiable, Equatable {
    let id: Int
    let name: String
    let sport: ProtoMapSport
    /// Départ et arrivée (et points de passage) : le tracé vient de Mapbox Directions.
    let waypoints: [Coordinate]
    var path: [Coordinate]
    var meters: Double
    /// Pente moyenne en %.
    let grade: Double
    let isVerified: Bool
    var isStarred: Bool
    let athletes: Int
    /// Meilleur temps du Classement (top 10 : gratuit).
    let leaderTime: String
    /// Mon meilleur Effort, si j'en ai un.
    let myBest: String?
    /// Inventé pour remplir le monde.
    var isSample = false

    var start: Coordinate { path.first ?? waypoints[0] }
    var line: [CLLocationCoordinate2D] { path.map(\.locationCoordinate) }

    /// Longueur (m) × pente (%), seuils de Strava ; rien sous 8 000.
    var category: String? {
        switch meters * grade {
        case 80_000...: "HC"
        case 64_000...: "Cat. 1"
        case 32_000...: "Cat. 2"
        case 16_000...: "Cat. 3"
        case 8_000...: "Cat. 4"
        default: nil
        }
    }

    func distance(from coordinate: Coordinate) -> Double { start.distance(to: coordinate).meters }
}

// MARK: - Caméra (zone visible approchée)

struct ProtoCamera: Equatable {
    var center: Coordinate
    var zoom: Double
    var size: CGSize

    static let initial = ProtoCamera(center: SegmentMapProto.me, zoom: SegmentMapProto.startZoom, size: CGSize(width: 400, height: 860))

    /// Mapbox : le monde fait 512 × 2^zoom points de large.
    var lonSpan: Double { Double(size.width) / (512 * pow(2, zoom)) * 360 }
    var latSpan: Double { Double(size.height) / (512 * pow(2, zoom)) * 360 * cos(center.latitude * .pi / 180) }

    func contains(_ coordinate: Coordinate) -> Bool {
        abs(coordinate.latitude - center.latitude) <= latSpan / 2
            && abs(coordinate.longitude - center.longitude) <= lonSpan / 2
    }

    /// Assez bougé (ou zoomé) pour que la zone cherchée ne corresponde plus.
    func differs(from other: ProtoCamera) -> Bool {
        abs(zoom - other.zoom) > 0.8
            || abs(center.latitude - other.center.latitude) > other.latSpan / 4
            || abs(center.longitude - other.center.longitude) > other.lonSpan / 4
    }
}

// MARK: - Store

enum ProtoMapRoute: Hashable {
    case segment(Int)
    case explore
}

@MainActor @Observable
final class ProtoMapStore {
    var segments: [ProtoMapSegment] = ProtoMapSamples.annecy + ProtoMapSamples.world
    var variant: String = UserDefaults.standard.string(forKey: "protoVariant") ?? "A"
    var pathsMessage: String? = "Chargement des tracés…"

    func segment(_ id: Int) -> ProtoMapSegment? { segments.first { $0.id == id } }

    func toggleStar(_ id: Int) {
        guard let index = segments.firstIndex(where: { $0.id == id }) else { return }
        segments[index].isStarred.toggle()
    }

    /// Tracés réels depuis Mapbox Directions ; sinon, la ligne droite des points de passage.
    func loadPaths(token: String) async {
        guard !token.isEmpty else { pathsMessage = "Pas de jeton Mapbox : tracés en ligne droite"; return }
        let targets = segments.filter { !$0.isSample }
        let results = await withTaskGroup(of: (Int, [Coordinate], Double)?.self) { group in
            for segment in targets {
                group.addTask { await Self.fetchPath(segment, token: token) }
            }
            var all: [(Int, [Coordinate], Double)] = []
            for await result in group { if let result { all.append(result) } }
            return all
        }
        for (id, path, meters) in results {
            if let index = segments.firstIndex(where: { $0.id == id }) {
                segments[index].path = path
                segments[index].meters = meters
            }
        }
        pathsMessage = results.count == targets.count ? nil : "Certains tracés en ligne droite (réseau)"
    }

    nonisolated private struct DirectionsResponse: Decodable {
        struct Route: Decodable {
            struct Geometry: Decodable { let coordinates: [[Double]] }
            let distance: Double
            let geometry: Geometry
        }
        let routes: [Route]
    }

    nonisolated private static func fetchPath(_ segment: ProtoMapSegment, token: String) async -> (Int, [Coordinate], Double)? {
        let points = segment.waypoints.map { "\($0.longitude),\($0.latitude)" }.joined(separator: ";")
        let url = URL(string: "https://api.mapbox.com/directions/v5/mapbox/\(segment.sport.routingProfile)/\(points)?geometries=geojson&overview=full&access_token=\(token)")!
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let route = try? JSONDecoder().decode(DirectionsResponse.self, from: data).routes.first,
              route.geometry.coordinates.count >= 2 else { return nil }
        let path = route.geometry.coordinates.map { Coordinate(latitude: $0[1], longitude: $0[0]) }
        return (segment.id, path, route.distance)
    }
}

// MARK: - Carte commune : style Outdoors, toi au Pâquier, caméra lue à l'arrêt

/// Pas AppMap : il suit le vrai GPS. Ici la position est simulée et la caméra remonte au repos.
struct ProtoMap<Content: MapContent>: View {
    @Binding var viewport: Viewport
    @Binding var camera: ProtoCamera
    var bottomInset: CGFloat = 0
    var ignoresSafeArea = true
    @MapContentBuilder let content: () -> Content

    @State private var box = CameraBox()

    final class CameraBox { var state: CameraState? }

    var body: some View {
        GeometryReader { geometry in
            Map(viewport: $viewport) {
                MapViewAnnotation(coordinate: SegmentMapProto.me.locationCoordinate) {
                    Circle().fill(.blue).frame(width: 18, height: 18)
                        .overlay(Circle().stroke(.white, lineWidth: 3)).shadow(radius: 2)
                }
                .allowOverlap(true)
                .allowHitTesting(false)
                content()
            }
            .mapStyle(.outdoors)
            .onCameraChanged { [box] event in box.state = event.cameraState }
            .onMapIdle { [box] _ in
                guard let state = box.state else { return }
                camera = ProtoCamera(center: Coordinate(latitude: state.center.latitude, longitude: state.center.longitude), zoom: state.zoom, size: geometry.size)
            }
            .additionalSafeAreaInsets(.bottom, bottomInset)
            .ignoresSafeArea(edges: ignoresSafeArea ? .all : [])
        }
    }
}

/// Tracés des Segments : gris foncé, celui mis en avant en orange avec départ et arrivée.
struct ProtoSegmentLines: MapContent {
    let segments: [ProtoMapSegment]
    let focusedID: Int?
    var color: UIColor = SegmentMapProto.lineColor
    var width: Double = 4
    let onTap: (Int) -> Void

    var body: some MapContent {
        PolylineAnnotationGroup(segments.filter { $0.id != focusedID }) { segment in
            PolylineAnnotation(lineCoordinates: segment.line)
                .lineColor(color)
                .lineWidth(width)
                .onTapGesture { _ in onTap(segment.id); return true }
        }
        .lineCap(.round)
        .lineJoin(.round)
        if let focused = segments.first(where: { $0.id == focusedID }) {
            PolylineAnnotation(lineCoordinates: focused.line)
                .lineColor(UIColor(Theme.accent))
                .lineWidth(6)
                .lineJoin(.round)
            RouteEndpointsContent(coordinates: focused.line)
        }
    }
}

extension ProtoMapSegment {
    func overview(top: Double = 140, bottom: Double = 40) -> Viewport {
        .overview(geometry: LineString(line), geometryPadding: EdgeInsets(top: top, leading: 50, bottom: bottom, trailing: 50))
    }
}

// MARK: - Bouts communs

enum ProtoMapFormat {
    static func grade(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1)).locale(ActivityFormatters.locale))) %"
    }

    static func distance(_ meters: Double) -> String { ActivityFormatters.distance(Distance(meters: meters)) }

    static func athletes(_ count: Int) -> String {
        "\(count.formatted(.number.locale(ActivityFormatters.locale))) athlète\(count > 1 ? "s" : "")"
    }

    /// « 1,2 km » ou « 350 m » de toi.
    static func away(_ meters: Double) -> String {
        meters < 1_000 ? "\(Int(meters / 50) * 50) m" : distance(meters)
    }
}

struct ProtoVerifiedSeal: View {
    var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .foregroundStyle(.blue)
            .accessibilityLabel("Segment vérifié")
    }
}

struct ProtoStarButton: View {
    let store: ProtoMapStore
    let id: Int

    var body: some View {
        let starred = store.segment(id)?.isStarred ?? false
        Button { store.toggleStar(id) } label: {
            Image(systemName: starred ? "star.fill" : "star")
                .foregroundStyle(starred ? .yellow : .secondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: starred)
        .accessibilityLabel(starred ? "Retirer des favoris" : "Ajouter aux favoris")
    }
}

/// « 6,8 km · 7,4 % · Cat. 2 »
struct ProtoSegmentStatsLine: View {
    let segment: ProtoMapSegment

    var body: some View {
        let parts = [ProtoMapFormat.distance(segment.meters), ProtoMapFormat.grade(segment.grade)] + (segment.category.map { [$0] } ?? [])
        Text(parts.joined(separator: " · ")).monospacedDigit()
    }
}

/// Le bouton « Créer » de la Carte, devenu un menu (décidé par le prototype de création).
struct ProtoCreateMenu: View {
    var body: some View {
        Menu {
            Button("Un Itinéraire", systemImage: "map") {}
            Button("Un Segment", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {}
        } label: {
            Label("Créer", systemImage: "plus")
                .font(.subheadline.bold())
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glassBackground(in: Capsule(), interactive: true)
        }
        .foregroundStyle(Theme.accent)
    }
}

/// Le carrousel d'Itinéraires d'aujourd'hui, réduit à une carte factice.
struct ProtoItineraryCarouselMock: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "bicycle").foregroundStyle(Theme.accent)
                Text("Tour du lac d'Annecy").font(.headline)
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary)
            }
            Text("42,2 km · 640 m D+ · Mes Itinéraires").font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(Theme.spacing)
        .background(Color(.systemBackground), in: .rect(cornerRadius: 20))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .padding(.horizontal, Theme.spacing)
    }
}

/// Puce de filtre (A, C).
struct ProtoChip: View {
    let title: String
    var symbol: String?
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(isOn ? .white : .primary)
            .background(isOn ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.regularMaterial), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Pastille violette ‹ › : pas une partie du design évalué.
struct ProtoMapSwitcher: View {
    @Binding var current: String
    static let variants = [("A", "Itinéraires | Segments"), ("B", "Calque Segments"), ("C", "Écran Segments")]

    var body: some View {
        HStack(spacing: 4) {
            Button { cycle(-1) } label: { Image(systemName: "chevron.left").frame(width: 30, height: 30) }
            VStack(spacing: 0) {
                Text("Variante \(current)").font(.caption.weight(.bold))
                Text(Self.variants.first { $0.0 == current }?.1 ?? "").font(.caption2)
            }
            .frame(minWidth: 140)
            Button { cycle(1) } label: { Image(systemName: "chevron.right").frame(width: 30, height: 30) }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.purple.opacity(0.92), in: Capsule())
        .shadow(radius: 6)
        .buttonStyle(.plain)
    }

    private func cycle(_ step: Int) {
        let keys = Self.variants.map(\.0)
        let index = keys.firstIndex(of: current) ?? 0
        current = keys[(index + step + keys.count) % keys.count]
    }
}

// MARK: - Racine : l'app réduite à ses onglets, la Carte prototypée

struct SegmentMapPrototypeView: View {
    @State private var store = ProtoMapStore()
    @State private var tab = 1
    /// `-protoExplore YES` : variante C ouverte sur l'écran Segments.
    @State private var path = NavigationPath(UserDefaults.standard.bool(forKey: "protoExplore") ? [ProtoMapRoute.explore] : [])
    @Environment(\.mapboxAccessToken) private var token

    var body: some View {
        @Bindable var store = store
        TabView(selection: $tab) {
            placeholder("Accueil").tabItem { Label("Accueil", systemImage: "house") }.tag(0)
            NavigationStack(path: $path) {
                Group {
                    switch store.variant {
                    case "B": ProtoMapVariantB(store: store)
                    case "C": ProtoMapVariantC(store: store)
                    default: ProtoMapVariantA(store: store)
                    }
                }
                .id(store.variant)
                .navigationDestination(for: ProtoMapRoute.self) { route in
                    switch route {
                    case .segment(let id): ProtoSegmentFicheStub(store: store, id: id)
                    case .explore: ProtoExploreScreen(store: store)
                    }
                }
            }
            .tabItem { Label("Map", systemImage: "map") }.tag(1)
            placeholder("Enregistrer").tabItem { Label("Enregistrer", systemImage: "record.circle") }.tag(2)
            placeholder("Profil").tabItem { Label("Profil", systemImage: "person") }.tag(3)
        }
        .overlay(alignment: .top) {
            VStack(spacing: 4) {
                ProtoMapSwitcher(current: $store.variant)
                if let message = store.pathsMessage {
                    Text(message).font(.caption2).padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.regularMaterial, in: Capsule())
                }
            }
        }
        .onChange(of: store.variant) { path = NavigationPath() }
        .task { await store.loadPaths(token: token) }
    }

    private func placeholder(_ title: String) -> some View {
        Text("\(title) (hors prototype)").foregroundStyle(.secondary)
    }
}

// MARK: - Fiche du Segment : un bouchon (prototype suivant)

struct ProtoSegmentFicheStub: View {
    let store: ProtoMapStore
    let id: Int

    var body: some View {
        if let segment = store.segment(id) {
            List {
                Section {
                    Map(initialViewport: segment.overview(top: 30, bottom: 30)) {
                        PolylineAnnotation(lineCoordinates: segment.line).lineColor(UIColor(Theme.accent)).lineWidth(5).lineJoin(.round)
                        RouteEndpointsContent(coordinates: segment.line)
                    }
                    .mapStyle(.outdoors)
                    .frame(height: 200)
                    .listRowInsets(EdgeInsets())
                }
                Section {
                    LabeledContent("Sport", value: segment.sport.label)
                    LabeledContent("Distance", value: ProtoMapFormat.distance(segment.meters))
                    LabeledContent("Pente moyenne", value: ProtoMapFormat.grade(segment.grade))
                    LabeledContent("Catégorie", value: segment.category ?? "—")
                    LabeledContent("Athlètes", value: ProtoMapFormat.athletes(segment.athletes))
                    LabeledContent("Meilleur temps", value: segment.leaderTime)
                    LabeledContent("Mon record", value: segment.myBest ?? "Pas encore d'Effort")
                } footer: {
                    Text("Bouchon : la fiche se décide dans « Prototype : fiche d'un Segment ».")
                }
            }
            .navigationTitle(segment.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { ProtoStarButton(store: store, id: id) }
                if segment.isVerified { ToolbarItem(placement: .topBarTrailing) { ProtoVerifiedSeal() } }
            }
        }
    }
}
#endif
