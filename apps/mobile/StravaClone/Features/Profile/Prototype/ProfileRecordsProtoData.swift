#if DEBUG
import Foundation

// PROTOTYPE — throwaway (voir ProfileRecordsProto.swift). Données inventées, graine fixe.

enum ProtoRecordSport: String, CaseIterable, Hashable, Identifiable {
    case run = "Course", ride = "Vélo", walk = "Marche", hike = "Randonnée", pool = "Piscine", openWater = "Eau libre"
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .run: "figure.run"
        case .ride: "figure.outdoor.cycle"
        case .walk: "figure.walk"
        case .hike: "figure.hiking"
        case .pool: "figure.pool.swim"
        case .openWater: "figure.open.water.swim"
        }
    }

    /// La puce de sport de Progrès qui montre ce sport (natation : piscine et eau libre).
    var sportType: SportType {
        switch self {
        case .run: .run
        case .ride: .ride
        case .walk: .walk
        case .hike: .hike
        case .pool, .openWater: .swim
        }
    }

    /// Distances de Record (#229).
    var distances: [(String, Double)] {
        switch self {
        case .run:
            [("400 m", 400), ("1 km", 1_000), ("2 km", 2_000), ("3 km", 3_000), ("5 km", 5_000), ("10 km", 10_000),
             ("15 km", 15_000), ("20 km", 20_000), ("Semi-marathon", 21_097.5), ("30 km", 30_000), ("Marathon", 42_195),
             ("50 km", 50_000), ("100 km", 100_000)]
        case .ride:
            [("5 km", 5_000), ("10 km", 10_000), ("20 km", 20_000), ("30 km", 30_000), ("40 km", 40_000), ("50 km", 50_000),
             ("80 km", 80_000), ("100 km", 100_000), ("150 km", 150_000), ("160 km", 160_000), ("200 km", 200_000)]
        case .walk:
            [("1 km", 1_000), ("2 km", 2_000), ("3 km", 3_000), ("5 km", 5_000), ("10 km", 10_000), ("Semi-marathon", 21_097.5),
             ("20 km", 20_000), ("30 km", 30_000), ("Marathon", 42_195)]
        case .hike:
            [("5 km", 5_000), ("10 km", 10_000), ("15 km", 15_000), ("20 km", 20_000), ("30 km", 30_000), ("40 km", 40_000), ("50 km", 50_000)]
        case .pool:
            [("50 m", 50), ("100 m", 100), ("200 m", 200), ("400 m", 400), ("800 m", 800), ("1 000 m", 1_000), ("1 500 m", 1_500)]
        case .openWater:
            [("400 m", 400), ("750 m", 750), ("1 km", 1_000), ("1,5 km", 1_500), ("1,9 km", 1_900), ("3,8 km", 3_800), ("5 km", 5_000), ("10 km", 10_000)]
        }
    }

    /// Allure affichée : /km à pied, km/h à vélo, /100 m en natation.
    func pace(seconds: Int, meters: Double) -> String {
        switch self {
        case .ride:
            return "\((meters / 1_000 / (Double(seconds) / 3_600)).formatted(.number.precision(.fractionLength(1)).locale(ActivityFormatters.locale))) km/h"
        case .pool, .openWater:
            return "\(ProtoProfileFormat.time(Int(Double(seconds) / meters * 100))) /100 m"
        default:
            return "\(ProtoProfileFormat.time(Int(Double(seconds) / meters * 1_000))) /km"
        }
    }
}

struct ProtoEffortTime: Identifiable, Hashable {
    let id: UUID
    let seconds: Int
    let date: Date
    let activity: String
    let visibility: ActivityVisibility
}

struct ProtoDistanceRecord: Identifiable {
    var id: String { label }
    let label: String
    let meters: Double
    let sport: ProtoRecordSport
    /// Le meilleur temps de chaque Activité sur cette distance (#229).
    let times: [ProtoEffortTime]

    var podium: [ProtoEffortTime] { Array(times.sorted { $0.seconds < $1.seconds }.prefix(3)) }
    var best: ProtoEffortTime { podium[0] }
    var byDate: [ProtoEffortTime] { times.sorted { $0.date > $1.date } }
    /// Le Record a moins de 30 jours.
    var isFresh: Bool { best.date > Date.now.addingTimeInterval(-30 * 86_400) }

    func medal(of time: ProtoEffortTime) -> Int? {
        podium.firstIndex(of: time).map { $0 + 1 }
    }
}

struct ProtoLegend: Identifiable {
    var id: Int { segmentID }
    let segmentID: Int
    /// Efforts sur 90 jours glissants.
    let count: Int
}

struct ProtoRecentEffort: Identifiable {
    let id = UUID()
    let segmentID: Int
    let daysAgo: Int
    let seconds: Int
    let medal: Int?
}

struct ProtoCreatedSegment: Identifiable {
    let id = UUID()
    let name: String
    let sport: ProtoMapSport
    let meters: Double
    let grade: Double
    let category: String?
    /// nil : rétro-appariement en cours.
    let athletes: Int?
}

enum ProtoProfileFormat {
    static func time(_ seconds: Int) -> String {
        let hours = seconds / 3_600, minutes = seconds / 60 % 60, rest = seconds % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().locale(ActivityFormatters.locale))
    }

    static func distance(_ meters: Double) -> String {
        meters >= 1_000
            ? "\((meters / 1_000).formatted(.number.precision(.fractionLength(1)).locale(ActivityFormatters.locale))) km"
            : "\(Int(meters)) m"
    }

    static func grade(_ grade: Double) -> String {
        "\(grade.formatted(.number.precision(.fractionLength(1)).locale(ActivityFormatters.locale))) %"
    }

    static func ago(_ days: Int) -> String {
        switch days {
        case 0: "Aujourd'hui"
        case 1: "Hier"
        default: "Il y a \(days) jours"
        }
    }
}

enum ProtoProfileSamples {
    // MARK: Meilleurs efforts

    /// Temps au km (ou au 100 m en natation) sur la plus courte distance, et la plus longue faite.
    private struct Profile {
        let base: Double
        let baseMeters: Double
        let maxMeters: Double
        let attempts: Int
    }

    private static let activityNames: [ProtoRecordSport: [String]] = [
        .run: ["Sortie du matin", "Fractionné au Pâquier", "Tour du lac", "10 km d'Annecy", "Footing du soir", "Semi d'Annecy", "Sortie longue", "Crêt du Maure"],
        .ride: ["Tour du lac d'Annecy", "Col de la Forclaz", "Semnoz", "Sortie du dimanche", "Aravis", "Vélo du soir", "Bauges"],
        .walk: ["Marche du midi", "Vieille ville", "Promenade du lac"],
        .hike: ["Mont Veyrier", "La Tournette", "Crêt de Châtillon", "Parmelan"],
        .pool: ["Natation à Jean Régis", "Séance 25 m", "Piscine des Marquisats"],
        .openWater: ["Traversée du lac", "Lac à Sévrier", "Baignade à Talloires"],
    ]

    private static func records(_ profiles: [ProtoRecordSport: Profile], seed: UInt64) -> [ProtoRecordSport: [ProtoDistanceRecord]] {
        var rng = ProtoRNG(seed: seed)
        var result: [ProtoRecordSport: [ProtoDistanceRecord]] = [:]
        for sport in ProtoRecordSport.allCases {
            guard let profile = profiles[sport] else { continue }
            let names = activityNames[sport] ?? ["Activité"]
            result[sport] = sport.distances.filter { $0.1 <= profile.maxMeters }.map { label, meters in
                // Riegel : t = t1 × (d / d1)^1,06 ; moins de passages sur les longues distances.
                let ideal = profile.base * pow(meters / profile.baseMeters, 1.06) * (sport == .ride ? 0.98 : 1)
                let count = max(1, Int(Double(profile.attempts) * (1 - meters / profile.maxMeters * 0.8)) + Int(rng.next() * 3))
                let times = (0..<count).map { _ in
                    let visibility: ActivityVisibility = rng.next() < 0.2 ? .private : (rng.next() < 0.2 ? .followers : .public)
                    return ProtoEffortTime(
                        id: UUID(),
                        seconds: Int(ideal * (1 + rng.next() * 0.22)),
                        date: .now.addingTimeInterval(-rng.next() * 3 * 365 * 86_400 - 86_400),
                        activity: names[Int(rng.next() * Double(names.count))],
                        visibility: visibility
                    )
                }
                return ProtoDistanceRecord(label: label, meters: meters, sport: sport, times: times)
            }
        }
        return result
    }

    static let myRecords = records([
        .run: Profile(base: 82, baseMeters: 400, maxMeters: 42_195, attempts: 14),
        .ride: Profile(base: 520, baseMeters: 5_000, maxMeters: 160_000, attempts: 12),
        .walk: Profile(base: 540, baseMeters: 1_000, maxMeters: 5_000, attempts: 5),
        .hike: Profile(base: 3_600, baseMeters: 5_000, maxMeters: 30_000, attempts: 6),
        .pool: Profile(base: 42, baseMeters: 50, maxMeters: 1_500, attempts: 9),
        .openWater: Profile(base: 520, baseMeters: 400, maxMeters: 1_900, attempts: 3),
    ], seed: 7)

    static let leaRecords = records([
        .run: Profile(base: 88, baseMeters: 400, maxMeters: 21_097.5, attempts: 10),
        .ride: Profile(base: 600, baseMeters: 5_000, maxMeters: 80_000, attempts: 5),
    ], seed: 11)

    // MARK: Segments (identifiants du prototype de carte, #237)

    static let myFavoriteIDs: Set<Int> = [1, 4, 8]
    static let leaFavoriteIDs: Set<Int> = [10, 8]

    static let myLegends = [ProtoLegend(segmentID: 4, count: 14), ProtoLegend(segmentID: 13, count: 9)]
    static let leaLegends = [ProtoLegend(segmentID: 10, count: 21)]

    static let myRecent = [
        ProtoRecentEffort(segmentID: 7, daysAgo: 1, seconds: 298, medal: 1),
        ProtoRecentEffort(segmentID: 3, daysAgo: 1, seconds: 552, medal: 2),
        ProtoRecentEffort(segmentID: 1, daysAgo: 6, seconds: 1_865, medal: nil),
        ProtoRecentEffort(segmentID: 8, daysAgo: 9, seconds: 161, medal: 1),
        ProtoRecentEffort(segmentID: 10, daysAgo: 9, seconds: 362, medal: 3),
        ProtoRecentEffort(segmentID: 4, daysAgo: 12, seconds: 391, medal: nil),
    ]
    static let leaRecent = [
        ProtoRecentEffort(segmentID: 10, daysAgo: 2, seconds: 301, medal: 1),
        ProtoRecentEffort(segmentID: 8, daysAgo: 2, seconds: 139, medal: 2),
    ]

    static let mySegments = [
        ProtoCreatedSegment(name: "Montée de la Puya", sport: .ride, meters: 2_300, grade: 6.4, category: "Cat. 4", athletes: 312),
        ProtoCreatedSegment(name: "Sprint du Thiou", sport: .run, meters: 420, grade: 0.2, category: nil, athletes: nil),
    ]
}
#endif
