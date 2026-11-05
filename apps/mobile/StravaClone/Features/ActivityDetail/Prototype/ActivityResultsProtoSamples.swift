#if DEBUG
import Foundation

// PROTOTYPE — throwaway (voir ActivityResultsProto.swift). La sortie et ses résultats, inventés.

enum ProtoResultsSamples {
    /// Annecy → Sévrier – Saint-Jorioz → Doussard → Montmin → Forclaz → Talloires → Menthon → Bluffy → Annecy.
    static let waypoints: [Coordinate] = [
        (45.9000, 6.1300), (45.8640, 6.1440), (45.8350, 6.1690), (45.7760, 6.2190), (45.8020, 6.2620),
        (45.8135, 6.2465), (45.8410, 6.2140), (45.8575, 6.1960), (45.8705, 6.2165), (45.8930, 6.1730), (45.9000, 6.1300),
    ].map { Coordinate(latitude: $0.0, longitude: $0.1) }

    /// Sans réseau : les points de passage reliés en ligne droite, densifiés.
    static let fallbackRoute: [Coordinate] = zip(waypoints, waypoints.dropFirst()).flatMap { from, to in
        (0..<40).map { step in
            let t = Double(step) / 40
            return Coordinate(latitude: from.latitude + (to.latitude - from.latitude) * t,
                              longitude: from.longitude + (to.longitude - from.longitude) * t)
        }
    } + [waypoints[waypoints.count - 1]]

    /// Ordre de la trace ; départ et arrivée = ceux des Segments du prototype de carte.
    private static let matched: [(ProtoSegmentResult, Coordinate, Coordinate)] = [
        (ProtoSegmentResult(id: 4, name: "Piste cyclable Sévrier – Saint-Jorioz", meters: 3_620, grade: 0.3, seconds: 372,
                            medal: 2, isFirstPass: false, rank: 58, athletes: 9_870),
         Coordinate(latitude: 45.8640, longitude: 6.1440), Coordinate(latitude: 45.8350, longitude: 6.1690)),
        (ProtoSegmentResult(id: 6, name: "Col de la Forclaz depuis Montmin", meters: 2_350, grade: 7.0, seconds: 598,
                            medal: 1, isFirstPass: true, rank: 214, athletes: 1_204),
         Coordinate(latitude: 45.8020, longitude: 6.2620), Coordinate(latitude: 45.8135, longitude: 6.2465)),
        (ProtoSegmentResult(id: 7, name: "Talloires – Menthon bord du lac", meters: 2_480, grade: 0.5, seconds: 321,
                            medal: nil, isFirstPass: false, rank: 1_840, athletes: 5_430),
         Coordinate(latitude: 45.8410, longitude: 6.2140), Coordinate(latitude: 45.8575, longitude: 6.1960)),
        (ProtoSegmentResult(id: 3, name: "Col de Bluffy", meters: 2_210, grade: 5.9, seconds: 527,
                            medal: 1, isFirstPass: false, rank: 1_120, athletes: 2_340),
         Coordinate(latitude: 45.8575, longitude: 6.1960), Coordinate(latitude: 45.8705, longitude: 6.2165)),
    ]

    static func segments(on route: [Coordinate]) -> [ProtoSegmentResult] {
        var from = 0
        return matched.map { result, start, end in
            var result = result
            let first = nearest(start, in: route, after: from)
            let last = max(nearest(end, in: route, after: first + 1), first + 1)
            result.range = first...min(last, route.count - 1)
            from = last
            return result
        }
    }

    private static func nearest(_ point: Coordinate, in route: [Coordinate], after start: Int) -> Int {
        guard start < route.count else { return route.count - 1 }
        return (start..<route.count).min { route[$0].distance(to: point).meters < route[$1].distance(to: point).meters } ?? start
    }

    static let rideRecords: [ProtoRecordResult] = [
        ProtoRecordResult(label: "5 km", meters: 5_000, seconds: 461, medal: 3, isFirstTime: false),
        ProtoRecordResult(label: "10 km", meters: 10_000, seconds: 962, medal: nil, isFirstTime: false),
        ProtoRecordResult(label: "20 km", meters: 20_000, seconds: 2_050, medal: 2, isFirstTime: false),
        ProtoRecordResult(label: "30 km", meters: 30_000, seconds: 3_525, medal: nil, isFirstTime: false),
        ProtoRecordResult(label: "40 km", meters: 40_000, seconds: 4_890, medal: 1, isFirstTime: false),
        ProtoRecordResult(label: "50 km", meters: 50_000, seconds: 6_252, medal: 1, isFirstTime: true),
    ]

    static let poolRecords: [ProtoRecordResult] = [
        ProtoRecordResult(label: "50 m", meters: 50, seconds: 41, medal: 1, isFirstTime: false),
        ProtoRecordResult(label: "100 m", meters: 100, seconds: 89, medal: 2, isFirstTime: false),
        ProtoRecordResult(label: "200 m", meters: 200, seconds: 188, medal: nil, isFirstTime: false),
        ProtoRecordResult(label: "400 m", meters: 400, seconds: 391, medal: 1, isFirstTime: false),
        ProtoRecordResult(label: "800 m", meters: 800, seconds: 802, medal: 3, isFirstTime: false),
        ProtoRecordResult(label: "1 000 m", meters: 1_000, seconds: 1_018, medal: nil, isFirstTime: false),
        ProtoRecordResult(label: "1 500 m", meters: 1_500, seconds: 1_547, medal: 1, isFirstTime: true),
    ]

    // MARK: - L'Activité renvoyée par le faux `GET /v1/activities/:id`

    @MainActor static func detail(id: ActivityID, state: ProtoResultsState) -> ActivityDetail {
        let author = state.isMine
            ? ActivityAuthor(id: "me", displayName: "Eliott Chiminello", avatarURL: nil)
            : ActivityAuthor(id: "1", displayName: "Camille Martin", avatarURL: nil)
        let engagement = ActivityEngagement(kudosCount: 6, commentCount: 1, viewerHasKudoed: false)
        if state.sport == .pool {
            return ActivityDetail(
                id: id, title: "Natation du midi", description: "Bassin de 25 m, 2 000 m dont 1 500 m sans arrêt.",
                sport: .swim, visibility: state.visibility, startedAt: .now.addingTimeInterval(-5 * 3_600),
                locationName: "Annecy, Haute-Savoie", source: .imported(.fit),
                stats: ActivityStats(distance: Distance(meters: 2_000), movingTime: .seconds(2_160), elapsedTime: .seconds(2_520),
                                     elevationGain: nil, avgSpeedMs: 0.93, maxSpeedMs: nil, avgHeartRate: 138, maxHeartRate: 161, calories: 520),
                route: nil, routeTrimmed: false, analysis: nil, author: author, engagement: engagement, viewerIsAuthor: state.isMine
            )
        }
        let route = state.route
        var cumulative = [0.0]
        for (a, b) in zip(route, route.dropFirst()) { cumulative.append(cumulative.last! + a.distance(to: b).meters) }
        let total = cumulative.last ?? 0
        let altitude = altitudes(route: route, segments: state.allSegments)
        let speed = route.indices.map { index -> Double in
            guard index > 0 else { return 8 }
            let climb = altitude[index] - altitude[index - 1]
            let step = max(cumulative[index] - cumulative[index - 1], 1)
            return max(3.2, min(13, 8.2 - 40 * climb / step))
        }
        return ActivityDetail(
            id: id, title: "Tour du lac par la Forclaz", description: "Montée par Montmin, retour par Bluffy. Vent du nord sur la piste cyclable.",
            sport: .ride, visibility: state.visibility, startedAt: .now.addingTimeInterval(-4 * 3_600),
            locationName: "Annecy, Haute-Savoie", source: .recorded,
            stats: ActivityStats(distance: Distance(meters: total), movingTime: .seconds(Int(total / 7.2)), elapsedTime: .seconds(Int(total / 6.6)),
                                 elevationGain: 1_160, avgSpeedMs: 7.2, maxSpeedMs: 17.8, avgHeartRate: 146, maxHeartRate: 181, calories: 1_840),
            route: EncodedPolyline(encoding: route), routeTrimmed: true,
            analysis: analysis(cumulative: cumulative, altitude: altitude, speed: speed),
            author: author, engagement: engagement, viewerIsAuthor: state.isMine
        )
    }

    /// 450 m au bord du lac, Forclaz à 1 150 m, Bluffy à 630 m.
    private static func altitudes(route: [Coordinate], segments: [ProtoSegmentResult]) -> [Double] {
        var altitude = Array(repeating: 450.0, count: route.count)
        guard segments.count == 4 else { return altitude }
        func ramp(_ range: ClosedRange<Int>, _ from: Double, _ to: Double) {
            for index in range { altitude[index] = from + (to - from) * Double(index - range.lowerBound) / Double(max(range.count - 1, 1)) }
        }
        let forclaz = segments[1].range, talloires = segments[2].range, bluffy = segments[3].range
        ramp(max(forclaz.lowerBound - 40, 0)...forclaz.lowerBound, 470, 760)
        ramp(forclaz, 760, 1_150)
        if forclaz.upperBound < talloires.lowerBound { ramp(forclaz.upperBound...talloires.lowerBound, 1_150, 450) }
        ramp(bluffy, 450, 630)
        let after = min(bluffy.upperBound + 60, route.count - 1)
        if bluffy.upperBound < after { ramp(bluffy.upperBound...after, 630, 450) }
        return altitude
    }

    private static func analysis(cumulative: [Double], altitude: [Double], speed: [Double]) -> ActivityAnalysis {
        var splits: [ActivitySplit] = []
        var start = 0
        for index in cumulative.indices where cumulative[index] - cumulative[start] >= 1_000 || index == cumulative.count - 1 {
            let meters = cumulative[index] - cumulative[start]
            guard meters > 50 else { continue }
            let average = speed[start...index].reduce(0, +) / Double(index - start + 1)
            splits.append(ActivitySplit(distance: Distance(meters: meters), movingTime: .seconds(Int(meters / average)),
                                        elevationDiff: altitude[index] - altitude[start], avgHeartRate: 130 + Int(min(50, max(0, (altitude[index] - altitude[start]) / 2))) ))
            start = index
        }
        let stride = max(cumulative.count / 300, 1)
        let picked = Array(Swift.stride(from: 0, to: cumulative.count, by: stride))
        return ActivityAnalysis(
            splits: splits,
            series: ActivitySeries(
                distanceM: picked.map { cumulative[$0] },
                speedMs: picked.map { speed[$0] },
                altitudeM: picked.map { altitude[$0] },
                heartRateBpm: picked.map { 128 + Int((altitude[$0] - 450) / 14) }
            )
        )
    }
}
#endif
