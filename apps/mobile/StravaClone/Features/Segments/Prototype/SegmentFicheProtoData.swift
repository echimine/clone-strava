#if DEBUG
import Foundation

// PROTOTYPE — throwaway (voir SegmentFicheProto.swift). Données inventées et règles décidées :
// Classement (#228), filtres (#233), Légende locale (#234), Premium (#235), Médailles (#228).

enum ProtoSex { case man, woman, other }

struct ProtoRider: Identifiable {
    struct Effort { let seconds: Int; let date: Date }

    let id: Int
    let name: String
    let sex: ProtoSex
    let age: Int?
    let weight: Double?
    let isFollowed: Bool
    /// Efforts d'Activités publiques, hors zone de confidentialité : ceux du Classement.
    let efforts: [Effort]
    /// Activités distinctes passées sur le Segment ces 90 derniers jours (Légende locale).
    let recentCount: Int

    var isMe: Bool { id == 0 }
}

/// Un de mes Efforts : tous, quelle que soit la visibilité de l'Activité.
struct ProtoMyEffort: Identifiable {
    let id: Int
    let date: Date
    let seconds: Int
    let isPublic: Bool
    /// Médaille personnelle à la date de l'Activité (1 or, 2 argent, 3 bronze).
    var medal: Int?
    /// C'est lui qui forme ma ligne au Classement « Tous » : seul à afficher un rang.
    var isBoardLine = false
}

enum ProtoSexFilter: String, CaseIterable, Identifiable {
    case all = "Tous", men = "Hommes", women = "Femmes"
    var id: String { rawValue }
}

/// Le seul autre filtre combinable au sexe.
enum ProtoOtherFilter: Hashable {
    case none, today, week, month, year, following, age(Int), weight(Int)

    static let periods: [ProtoOtherFilter] = [.today, .week, .month, .year]
    static let ageBands: [(String, ClosedRange<Int>)] = [
        ("19 ans et moins", 0...19), ("20-24 ans", 20...24), ("25-34 ans", 25...34), ("35-44 ans", 35...44),
        ("45-54 ans", 45...54), ("55-64 ans", 55...64), ("65-69 ans", 65...69), ("70-74 ans", 70...74), ("75 ans et plus", 75...200),
    ]
    static let weightBands: [(String, ClosedRange<Double>)] = [
        ("54 kg et moins", 0...54.999), ("55-64 kg", 55...64.999), ("65-74 kg", 65...74.999), ("75-84 kg", 75...84.999),
        ("85-94 kg", 85...94.999), ("95-104 kg", 95...104.999), ("105-114 kg", 105...114.999), ("115 kg et plus", 115...500),
    ]

    var label: String {
        switch self {
        case .none: "Aucun filtre"
        case .today: "Aujourd'hui"
        case .week: "Cette semaine"
        case .month: "Ce mois-ci"
        case .year: "Cette année"
        case .following: "Abonnements"
        case .age(let index): Self.ageBands[index].0
        case .weight(let index): Self.weightBands[index].0
        }
    }
}

struct ProtoBoardRow: Identifiable {
    let rank: Int
    let rider: ProtoRider
    let seconds: Int
    let date: Date
    var id: Int { rider.id }
}

struct ProtoBoard {
    let rows: [ProtoBoardRow]
    var me: ProtoBoardRow? { rows.first { $0.rider.isMe } }
}

// MARK: - Fiche

struct ProtoFicheData {
    let segment: ProtoMapSegment
    let riders: [ProtoRider]
    let myEfforts: [ProtoMyEffort]
    let profile: ElevationProfile
    let starCount: Int

    var gain: Double { segment.meters * segment.grade / 100 }
    var myRecentCount: Int { riders.first { $0.isMe }?.recentCount ?? 0 }
    var myBest: ProtoMyEffort? { myEfforts.min { ($0.seconds, $0.date) < ($1.seconds, $1.date) } }

    init(segment: ProtoMapSegment, hasEfforts: Bool) {
        self.segment = segment
        var rng = ProtoRNG(seed: UInt64(segment.id) &* 7_919 &+ 11)
        let leader = Self.seconds(segment.leaderTime)
        let now = Date()
        let day = 86_400.0

        // Mes Efforts, du plus ancien au plus récent ; le meilleur est sur une Activité privée.
        var mine: [ProtoMyEffort] = []
        if hasEfforts {
            let best = segment.myBest.map(Self.seconds) ?? Int(Double(leader) * 1.35)
            let plan: [(Double, Double, Bool)] = [(1.18, 690, true), (1.09, 410, true), (1.0, 230, false), (1.04, 38, true), (1.12, 6, true)]
            mine = plan.enumerated().map { index, step in
                ProtoMyEffort(id: index, date: now.addingTimeInterval(-step.1 * day), seconds: Int(Double(best) * step.0), isPublic: step.2)
            }
            for index in mine.indices {
                let before = mine[..<index]
                let better = before.filter { $0.seconds <= mine[index].seconds }.count
                mine[index].medal = better < 3 ? better + 1 : nil
            }
            if let line = mine.filter(\.isPublic).min(by: { ($0.seconds, $0.date) < ($1.seconds, $1.date) }),
               let index = mine.firstIndex(where: { $0.id == line.id }) {
                mine[index].isBoardLine = true
            }
        }
        myEfforts = mine

        var riders = [ProtoRider(
            id: 0, name: "Eliott C.", sex: .man, age: 31, weight: 72, isFollowed: true,
            efforts: mine.filter(\.isPublic).map { ProtoRider.Effort(seconds: $0.seconds, date: $0.date) },
            recentCount: hasEfforts ? 3 : 0
        )]
        var tie = 0
        for id in 1..<140 {
            let roll = rng.next()
            let sex: ProtoSex = roll < 0.04 ? .other : (roll < 0.36 ? .woman : .man)
            let names = sex == .woman ? Self.women : Self.men
            let name = "\(names[Int(rng.next() * Double(names.count))]) \(Self.initials[Int(rng.next() * Double(Self.initials.count))])."
            var best = id == 1 ? leader : Int(Double(leader) * (1 + 1.1 * pow(rng.next(), 1.25)))
            if id == 4 { tie = best }
            if id == 5 { best = tie }
            let count = 1 + Int(rng.next() * 5)
            let efforts = (0..<count).map { index in
                ProtoRider.Effort(
                    seconds: index == 0 ? best : Int(Double(best) * (1 + 0.12 * rng.next())),
                    date: now.addingTimeInterval(-(pow(rng.next(), 2.2) * 1_100 + 0.02) * day)
                )
            }
            riders.append(ProtoRider(
                id: id, name: name, sex: sex,
                age: 16 + Int(rng.next() * 62),
                weight: rng.next() < 0.2 ? nil : 48 + rng.next() * 62,
                isFollowed: rng.next() < 0.1,
                efforts: efforts,
                recentCount: id == 7 ? 17 : (id == 23 ? 11 : Int(pow(rng.next(), 5) * 12))
            ))
        }
        self.riders = riders
        starCount = Int(Double(segment.athletes) * 0.07)

        // Profil d'altitude inventé : la pente moyenne et un peu de relief.
        let steps = 80
        profile = ElevationProfile(points: (0...steps).map { index in
            let meters = segment.meters * Double(index) / Double(steps)
            let wave = sin(meters / 260) * min(segment.grade, 6) * 2.2
            return ElevationProfile.Point(distance: Distance(meters: meters), altitude: 450 + meters * segment.grade / 100 + wave)
        })
    }

    // MARK: Classement

    func board(sex: ProtoSexFilter, other: ProtoOtherFilter, now: Date = .now) -> ProtoBoard {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let start: Date? = switch other {
        case .today: calendar.startOfDay(for: now)
        case .week: calendar.dateInterval(of: .weekOfYear, for: now)?.start
        case .month: calendar.dateInterval(of: .month, for: now)?.start
        case .year: calendar.dateInterval(of: .year, for: now)?.start
        default: nil
        }
        let entries: [(ProtoRider, ProtoRider.Effort)] = riders.compactMap { rider in
            guard matches(rider, sex: sex, other: other) else { return nil }
            let efforts = rider.efforts.filter { start == nil || $0.date >= start! }
            guard let best = efforts.min(by: { ($0.seconds, $0.date) < ($1.seconds, $1.date) }) else { return nil }
            return (rider, best)
        }
        .sorted { ($0.1.seconds, $0.1.date) < ($1.1.seconds, $1.1.date) }

        var rows: [ProtoBoardRow] = []
        for (index, entry) in entries.enumerated() {
            let rank = index > 0 && rows[index - 1].seconds == entry.1.seconds ? rows[index - 1].rank : index + 1
            rows.append(ProtoBoardRow(rank: rank, rider: entry.0, seconds: entry.1.seconds, date: entry.1.date))
        }
        return ProtoBoard(rows: rows)
    }

    private func matches(_ rider: ProtoRider, sex: ProtoSexFilter, other: ProtoOtherFilter) -> Bool {
        switch sex {
        case .all: break
        case .men: guard rider.sex == .man else { return false }
        case .women: guard rider.sex == .woman else { return false }
        }
        switch other {
        case .following: return rider.isFollowed || rider.isMe
        case .age(let index): return rider.age.map { ProtoOtherFilter.ageBands[index].1.contains($0) } ?? false
        case .weight(let index): return rider.weight.map { ProtoOtherFilter.weightBands[index].1.contains($0) } ?? false
        default: return true
        }
    }

    /// Le plus d'Efforts sur 90 jours ; à égalité, le premier arrivé (ici, le plus petit id).
    func legend(sex: ProtoSexFilter) -> (rider: ProtoRider, count: Int)? {
        let candidates = riders.filter { matches($0, sex: sex, other: .none) && $0.recentCount > 0 }
        guard let top = candidates.max(by: { ($0.recentCount, -$0.id) < ($1.recentCount, -$1.id) }) else { return nil }
        return (top, top.recentCount)
    }

    // MARK: Bouts

    static func seconds(_ text: String) -> Int {
        text.split(separator: ":").reduce(0) { $0 * 60 + (Int($1) ?? 0) }
    }

    static func time(_ seconds: Int) -> String {
        let hours = seconds / 3_600, minutes = seconds / 60 % 60, rest = seconds % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().locale(ActivityFormatters.locale))
    }

    private static let men = ["Lucas", "Hugo", "Louis", "Jules", "Arthur", "Nathan", "Tom", "Théo", "Paul", "Maxime", "Romain", "Antoine", "Baptiste", "Quentin", "Victor", "Mathis", "Adrien", "Julien"]
    private static let women = ["Camille", "Léa", "Chloé", "Manon", "Inès", "Sarah", "Julie", "Emma", "Clara", "Zoé", "Anaïs", "Elsa", "Lina", "Margaux", "Pauline", "Lou"]
    private static let initials = ["B", "C", "D", "F", "G", "L", "M", "P", "R", "S", "T", "V"]
}

struct ProtoRNG {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(UInt64(1) << 53)
    }
}
#endif
