#if DEBUG
import Foundation

// PROTOTYPE — throwaway (voir SegmentMapProto.swift).
// Annecy : départ et arrivée réels, tracé demandé à Mapbox Directions. Ailleurs : inventé.

enum ProtoMapSamples {
    private static func seg(
        _ id: Int, _ name: String, _ sport: ProtoMapSport, _ waypoints: [(Double, Double)],
        grade: Double, verified: Bool = false, starred: Bool = false,
        athletes: Int, leader: String, mine: String? = nil
    ) -> ProtoMapSegment {
        let points = waypoints.map { Coordinate(latitude: $0.0, longitude: $0.1) }
        let meters = zip(points, points.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1).meters }
        return ProtoMapSegment(
            id: id, name: name, sport: sport, waypoints: points, path: points, meters: meters,
            grade: grade, isVerified: verified, isStarred: starred, athletes: athletes,
            leaderTime: leader, myBest: mine
        )
    }

    static let annecy: [ProtoMapSegment] = [
        seg(1, "Col de la Forclaz depuis Talloires", .ride, [(45.8410, 6.2140), (45.8135, 6.2465)],
            grade: 7.4, verified: true, starred: true, athletes: 4_812, leader: "21:37", mine: "31:05"),
        seg(2, "Semnoz depuis Quintal", .ride, [(45.8287, 6.0920), (45.7860, 6.1060)],
            grade: 8.0, verified: true, athletes: 6_203, leader: "38:12"),
        seg(3, "Col de Bluffy", .ride, [(45.8575, 6.1960), (45.8705, 6.2165)],
            grade: 5.9, athletes: 2_340, leader: "6:48", mine: "9:12"),
        seg(4, "Piste cyclable Sévrier – Saint-Jorioz", .ride, [(45.8640, 6.1440), (45.8350, 6.1690)],
            grade: 0.3, starred: true, athletes: 9_870, leader: "5:02", mine: "6:31"),
        seg(5, "Côte de Vieugy", .ride, [(45.8790, 6.1050), (45.8680, 6.0880)],
            grade: 6.1, athletes: 1_512, leader: "4:55"),
        seg(6, "Col de la Forclaz depuis Montmin", .ride, [(45.8020, 6.2620), (45.8135, 6.2465)],
            grade: 7.0, verified: true, athletes: 1_204, leader: "8:40"),
        seg(7, "Talloires – Menthon bord du lac", .ride, [(45.8410, 6.2140), (45.8575, 6.1960)],
            grade: 0.5, athletes: 5_430, leader: "3:41", mine: "4:58"),
        seg(8, "Sprint du Pâquier", .run, [(45.9000, 6.1300), (45.9045, 6.1420)],
            grade: 0.1, starred: true, athletes: 3_120, leader: "2:02", mine: "2:41"),
        seg(9, "Crêt du Maure", .run, [(45.8890, 6.1150), (45.8770, 6.1125)],
            grade: 11.2, athletes: 1_045, leader: "7:15"),
        seg(10, "Bord du lac des Marquisats", .run, [(45.8935, 6.1335), (45.8805, 6.1430)],
            grade: 0.2, verified: true, athletes: 4_388, leader: "4:31", mine: "6:02"),
        seg(11, "Mont Veyrier par les Contrebandiers", .hike, [(45.9140, 6.1630), (45.9165, 6.1765)],
            grade: 24.0, verified: true, athletes: 2_011, leader: "28:40"),
        seg(12, "Crêt de Châtillon", .hike, [(45.7840, 6.1050), (45.7795, 6.1070)],
            grade: 12.0, athletes: 876, leader: "5:58"),
        seg(13, "Vieille ville et canal du Thiou", .walk, [(45.8985, 6.1235), (45.8995, 6.1295)],
            grade: 0.4, athletes: 412, leader: "4:10", mine: "6:44"),
    ]

    /// Villes autour : des Segments inventés, pour voir la Carte à l'échelle d'une région.
    static let world: [ProtoMapSegment] = {
        let cities: [(String, Double, Double, Int)] = [
            ("Chambéry", 45.566, 5.920, 18), ("Genève", 46.204, 6.143, 24), ("Grenoble", 45.188, 5.724, 26),
            ("Lyon", 45.764, 4.835, 40), ("Chamonix", 45.923, 6.869, 22), ("Albertville", 45.676, 6.392, 12),
            ("Thônes", 45.881, 6.325, 9), ("Aix-les-Bains", 45.688, 5.915, 14), ("Annemasse", 46.193, 6.234, 10),
        ]
        var generator = LCG(seed: 42)
        var result: [ProtoMapSegment] = []
        var id = 100
        for (city, lat, lon, count) in cities {
            for index in 0..<count {
                let sport = ProtoMapSport.allCases[Int(generator.next() * 4)]
                var point = Coordinate(latitude: lat + (generator.next() - 0.5) * 0.12, longitude: lon + (generator.next() - 0.5) * 0.16)
                var heading = generator.next() * 2 * .pi
                var points = [point]
                let step = sport == .ride ? 0.006 : 0.002
                for _ in 0..<5 {
                    heading += (generator.next() - 0.5) * 0.9
                    point = Coordinate(latitude: point.latitude + cos(heading) * step, longitude: point.longitude + sin(heading) * step * 1.4)
                    points.append(point)
                }
                let meters = zip(points, points.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1).meters }
                let grade = (generator.next() * 10).rounded() / 1 + (generator.next() > 0.6 ? 0 : -generator.next() * 3)
                var segment = ProtoMapSegment(
                    id: id, name: "Exemple \(city) \(index + 1)", sport: sport, waypoints: points, path: points,
                    meters: meters, grade: max(grade, 0.2), isVerified: generator.next() > 0.8, isStarred: false,
                    athletes: Int(generator.next() * 3_000) + 20, leaderTime: "\(Int(generator.next() * 20) + 2):\(String(format: "%02d", Int(generator.next() * 60)))",
                    myBest: nil
                )
                segment.isSample = true
                result.append(segment)
                id += 1
            }
        }
        return result
    }()

    private struct LCG {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(UInt64(1) << 53)
        }
    }
}
#endif
