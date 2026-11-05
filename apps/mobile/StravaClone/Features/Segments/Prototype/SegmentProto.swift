#if DEBUG
import CoreLocation
import SwiftUI

// PROTOTYPE — throwaway. Ticket « Prototype : créer un Segment dans l'app iOS » (#236), carte
// « Segments et Records dans l'app » (#223). Branche prototype/segment-creation, jamais fusionnée.
//
// Lancement : argument `-SegmentCreationPrototype` (Edit Scheme > Run > Arguments), à la place de l'app.
// Quatre onglets : Entrées (où l'on crée un Segment), Extraire (trois variantes pour choisir le début
// et la fin sur une Activité, cyclées par la pastille ‹ ›), Dessiner (sur la carte), Mes Segments.
// Le menu « Serveur » (en haut) choisit la réponse simulée à « Créer » : OK, doublon ou quota atteint.
// Tout est en mémoire : rien n'est envoyé.

enum SegmentProto {
    static let launchArgument = "-SegmentCreationPrototype"

    struct TrackPoint {
        let coordinate: Coordinate
        let altitude: Double
        /// Secondes depuis le départ.
        let time: Int

        init(_ latitude: Double, _ longitude: Double, _ altitude: Double, _ time: Int) {
            coordinate = Coordinate(latitude: latitude, longitude: longitude)
            self.altitude = altitude
            self.time = time
        }
    }
}

// MARK: - Sport

enum ProtoSegmentSport: String, CaseIterable, Identifiable {
    case run, ride, walk, hike
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
    /// 200 m à pied, 500 m à vélo.
    var minimumMeters: Double { self == .ride ? 500 : 200 }
}

// MARK: - Activité d'exemple

/// La trace nettoyée d'une Activité, sa zone de confidentialité au départ et ses Pauses.
struct ProtoTrack {
    let title: String
    let sport: ProtoSegmentSport
    let points: [SegmentProto.TrackPoint]
    /// Distance cumulée au point i.
    let cumulative: [Double]
    /// Les points dans la zone de confidentialité (autour du départ) : jamais dans un Segment.
    let privateRange: ClosedRange<Int>?
    /// Points i où (i-1 → i) est une Pause ou un trou de plus de 30 s.
    let gapIndices: [Int]

    static let sample: ProtoTrack = {
        // Altitude lissée sur 9 points : le modèle de terrain est bruité dans les lacets.
        let raw = SegmentProto.samplePoints
        let points = raw.indices.map { index in
            let window = raw[max(index - 4, 0)...min(index + 4, raw.count - 1)]
            let altitude = window.map(\.altitude).reduce(0, +) / Double(window.count)
            return SegmentProto.TrackPoint(raw[index].coordinate.latitude, raw[index].coordinate.longitude, altitude, raw[index].time)
        }
        var cumulative = [0.0]
        for index in 1..<points.count {
            cumulative.append(cumulative[index - 1] + points[index - 1].coordinate.distance(to: points[index].coordinate).meters)
        }
        let home = points[0].coordinate
        let lastPrivate = points.lastIndex { $0.coordinate.distance(to: home).meters < 600 } ?? 0
        let gaps = (1..<points.count).filter { index in
            let seconds = points[index].time - points[index - 1].time
            let meters = cumulative[index] - cumulative[index - 1]
            // Plus de 30 s pour quelques dizaines de mètres : un arrêt.
            return seconds > 30 && meters / Double(seconds) < 1.5
        }
        return ProtoTrack(
            title: "Annecy – col de la Forclaz",
            sport: .ride,
            points: points,
            cumulative: cumulative,
            privateRange: 0...lastPrivate,
            gapIndices: gaps
        )
    }()

    var coordinates: [CLLocationCoordinate2D] { points.map(\.coordinate.locationCoordinate) }
    var totalMeters: Double { cumulative.last ?? 0 }
    /// Premier point qu'on peut choisir comme départ.
    var firstAllowed: Int { (privateRange?.upperBound ?? -1) + 1 }

    func index(atMeters meters: Double) -> Int {
        cumulative.firstIndex { $0 >= meters } ?? points.count - 1
    }

    func nearestIndex(to coordinate: Coordinate) -> Int {
        points.indices.min {
            points[$0].coordinate.distance(to: coordinate).meters < points[$1].coordinate.distance(to: coordinate).meters
        } ?? 0
    }

    func portion(_ range: ClosedRange<Int>) -> ProtoPortion {
        ProtoPortion(
            sport: sport,
            coordinates: Array(points[range].map(\.coordinate)),
            altitudes: Array(points[range].map(\.altitude)),
            distances: Array(cumulative[range].map { $0 - cumulative[range.lowerBound] }),
            containsGap: gapIndices.contains { $0 > range.lowerBound && $0 <= range.upperBound },
            touchesPrivateZone: privateRange.map { $0.overlaps(range) } ?? false
        )
    }
}

// MARK: - Une portion candidate : stats et garde-fous

/// Ce qui deviendra le tracé du Segment. Dans l'app, l'altitude vient de l'`ElevationService`
/// et le calcul est refait par le serveur ; ici, l'altitude de la trace suffit.
struct ProtoPortion {
    let sport: ProtoSegmentSport
    let coordinates: [Coordinate]
    let altitudes: [Double]
    let distances: [Double]
    var containsGap = false
    var touchesPrivateZone = false

    var meters: Double { distances.last ?? 0 }

    /// Hystérésis de 5 m : le bruit du modèle de terrain ne compte pas.
    var elevationGain: Double {
        guard var reference = altitudes.first else { return 0 }
        var gain = 0.0
        for altitude in altitudes.dropFirst() {
            if altitude - reference >= 5 { gain += altitude - reference; reference = altitude }
            else if reference - altitude >= 5 { reference = altitude }
        }
        return gain
    }

    var averageGrade: Double {
        guard meters > 0, let first = altitudes.first, let last = altitudes.last else { return 0 }
        return (last - first) / meters * 100
    }

    /// Sur des fenêtres d'au moins 200 m.
    var maxGrade: Double {
        var best = averageGrade
        var start = 0
        for end in distances.indices {
            while start < end, distances[end] - distances[start] > 200 { start += 1 }
            let run = distances[end] - distances[max(start - 1, 0)]
            if run >= 200 {
                best = max(best, (altitudes[end] - altitudes[max(start - 1, 0)]) / run * 100)
            }
        }
        return best
    }

    var lowest: Double { altitudes.min() ?? 0 }
    var highest: Double { altitudes.max() ?? 0 }

    /// Longueur (m) × pente (%), les seuils de Strava ; rien sous 8 000.
    var category: String? {
        let score = meters * averageGrade
        switch score {
        case 80_000...: return "HC"
        case 64_000...: return "Cat. 1"
        case 32_000...: return "Cat. 2"
        case 16_000...: return "Cat. 3"
        case 8_000...: return "Cat. 4"
        default: return nil
        }
    }

    /// Le premier garde-fou qui bloque, dans l'ordre où l'athlète peut le corriger.
    var problem: ProtoProblem? {
        if touchesPrivateZone { return .privateZone }
        if coordinates.count < 2 || meters < sport.minimumMeters { return .tooShort(sport) }
        if meters > 50_000 { return .tooLong }
        if let first = coordinates.first, let last = coordinates.last, first.distance(to: last).meters < 100 {
            return .loop
        }
        if containsGap { return .pause }
        return nil
    }

    var profile: ElevationProfile {
        ElevationProfile(points: zip(distances, altitudes).map { .init(distance: Distance(meters: $0), altitude: $1) })
    }
}

enum ProtoProblem: Equatable {
    case privateZone, tooShort(ProtoSegmentSport), tooLong, loop, pause

    var message: String {
        switch self {
        case .privateZone: "Un Segment ne peut pas entrer dans ta zone de confidentialité."
        case .tooShort(let sport): sport == .ride ? "Trop court : au moins 500 m à vélo." : "Trop court : au moins 200 m."
        case .tooLong: "Trop long : 50 km au plus."
        case .loop: "Le départ et l'arrivée doivent être à plus de 100 m l'un de l'autre."
        case .pause: "Cette portion contient une Pause. Choisis une portion sans arrêt."
        }
    }
}

// MARK: - Réponse simulée du serveur

enum ProtoServerReply: String, CaseIterable, Identifiable {
    case created = "Créé"
    case duplicate = "Doublon"
    case quota = "Quota atteint"
    var id: String { rawValue }
}

// MARK: - Mes Segments

struct ProtoMySegment: Identifiable {
    let id = UUID()
    var name: String
    let sport: ProtoSegmentSport
    let meters: Double
    let grade: Double
    let category: String?
    /// Autres athlètes avec un Effort : au-delà de 0, le créateur ne peut plus supprimer.
    var otherAthletes: Int
    let createdAt: Date
    var isMatching = false
}

@Observable
final class ProtoStore {
    var mySegments: [ProtoMySegment] = [
        ProtoMySegment(name: "Montée de Talloires", sport: .ride, meters: 4_120, grade: 5.8, category: "Cat. 3", otherAthletes: 37, createdAt: .now.addingTimeInterval(-86_400 * 40)),
        ProtoMySegment(name: "Sprint du Pâquier", sport: .run, meters: 650, grade: 0.2, category: nil, otherAthletes: 0, createdAt: .now.addingTimeInterval(-86_400 * 3)),
        ProtoMySegment(name: "Sentier du Mont Veyrier", sport: .hike, meters: 2_900, grade: 18.4, category: "Cat. 1", otherAthletes: 4, createdAt: .now.addingTimeInterval(-86_400 * 12)),
    ]
    var reply: ProtoServerReply = .created
    var createdToday = 3
    /// `-protoTab extract|draw|mine` au lancement ; variantes : `-protoExtract B`.
    var selectedTab: ProtoTab = ProtoTab(rawValue: UserDefaults.standard.string(forKey: "protoTab") ?? "") ?? .entries
    /// Ouvert depuis un point d'entrée : le flux d'extraction ou de dessin en plein écran.
    var flow: ProtoFlow?

    func create(name: String, portion: ProtoPortion) -> ProtoCreateResult {
        switch reply {
        case .duplicate:
            return .duplicate(existing: "Col de la Forclaz depuis Talloires")
        case .quota:
            return .quota
        case .created:
            createdToday += 1
            mySegments.insert(
                ProtoMySegment(
                    name: name, sport: portion.sport, meters: portion.meters, grade: portion.averageGrade,
                    category: portion.category, otherAthletes: 0, createdAt: .now, isMatching: true
                ),
                at: 0
            )
            return .created
        }
    }
}

enum ProtoTab: String, Hashable { case entries, extract, draw, mine }

enum ProtoFlow: Identifiable {
    case extract, draw, pickActivity
    var id: Self { self }
}

enum ProtoCreateResult: Equatable {
    case created, duplicate(existing: String), quota
}

// MARK: - Bouts communs

struct ProtoVariant {
    let key: String
    let name: String
}

/// Pastille violette ‹ › : pas une partie du design évalué.
struct ProtoSwitcher: View {
    let title: String
    let variants: [ProtoVariant]
    @Binding var current: String

    var body: some View {
        HStack(spacing: 4) {
            Button { cycle(-1) } label: { Image(systemName: "chevron.left").frame(width: 32, height: 32) }
            VStack(spacing: 0) {
                Text("\(title) \(current)").font(.caption.weight(.bold))
                Text(variants.first { $0.key == current }?.name ?? "").font(.caption2)
            }
            .frame(minWidth: 150)
            Button { cycle(1) } label: { Image(systemName: "chevron.right").frame(width: 32, height: 32) }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.purple.opacity(0.9), in: Capsule())
        .shadow(radius: 6)
        .buttonStyle(.plain)
        .padding(.bottom, 6)
    }

    private func cycle(_ step: Int) {
        let keys = variants.map(\.key)
        let index = keys.firstIndex(of: current) ?? 0
        withAnimation(.snappy) { current = keys[(index + step + keys.count) % keys.count] }
    }
}

enum ProtoFormat {
    static func grade(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1)).locale(ActivityFormatters.locale))) %"
    }

    static func distance(_ meters: Double) -> String {
        ActivityFormatters.distance(Distance(meters: meters))
    }
}

extension ProtoProblem {
    var banner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.footnote).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}
#endif
