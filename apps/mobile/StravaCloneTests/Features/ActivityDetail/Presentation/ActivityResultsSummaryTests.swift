import Foundation
import Testing
@testable import StravaClone

/// « Résultats » of the detail, as Strava shows it (ADR-039 §15, spec #252): three counters,
/// at most 3 medalled lines (Best efforts first, then Segments in trace order), time and pace.
struct ActivityResultsSummaryTests {
    private func results(
        matching: Bool = false,
        pool: Double? = nil,
        bestEfforts: [BestEffortResult] = [],
        efforts: [SegmentEffortResult] = []
    ) -> ActivityResults {
        ActivityResults(
            matchingInProgress: matching,
            poolLength: pool.map { Distance(meters: $0) },
            bestEfforts: bestEfforts,
            efforts: efforts
        )
    }

    @Test func countsBestEffortsSegmentsAndMedals() {
        let summary = ActivityResultsSummary(results: results(
            bestEfforts: [.fixture(distanceM: 400, medal: .gold), .fixture(distanceM: 1_000)],
            efforts: [.fixture(medal: .silver), .fixture(medal: .bronze), .fixture()]
        ), sport: .run)

        #expect(summary.counters == [
            .init(label: "Meilleurs efforts", value: "2"),
            .init(label: "Segments", value: "3"),
            .init(label: "Performances", value: "3"),
        ])
    }

    /// While matching, the Segments counter shows « … » and a line says the search goes on.
    @Test func whileMatchingTheSegmentsCounterWaits() {
        let summary = ActivityResultsSummary(results: results(matching: true, bestEfforts: [.fixture()]), sport: .run)

        #expect(summary.counters[1] == .init(label: "Segments", value: "…"))
        #expect(summary.showsMatching)
        #expect(!summary.isEmpty)
    }

    /// No Segments counter for a pool swim.
    @Test func aPoolSwimHasNoSegmentsCounter() {
        let summary = ActivityResultsSummary(results: results(pool: 25, bestEfforts: [.fixture(distanceM: 100)]), sport: .swim)

        #expect(summary.counters.map(\.label) == ["Meilleurs efforts", "Performances"])
    }

    @Test func noResultNoSection() {
        #expect(ActivityResultsSummary(results: .empty, sport: .run).isEmpty)
    }

    @Test func showsAtMostThreeMedalledLinesBestEffortsFirst() {
        let summary = ActivityResultsSummary(results: results(
            bestEfforts: [.fixture(distanceM: 400), .fixture(distanceM: 1_000, seconds: 280, medal: .silver)],
            efforts: [
                .fixture(id: "a", name: "Reference Albigny", distanceM: 370, seconds: 131, medal: .gold),
                .fixture(id: "b", name: "Petit Port", medal: .bronze, isFirstPass: false),
                .fixture(id: "c", name: "Bonlieu", medal: .gold),
            ]
        ), sport: .run)

        #expect(summary.lines.map(\.title) == ["1 KM", "Reference Albigny", "Petit Port"])
        #expect(summary.lines[0] == ActivityResultLine(
            id: "best-1000.0",
            target: .bestEffort(distanceM: 1_000),
            medal: .silver,
            title: "1 KM",
            figures: ["4:40", "4:40 /km"],
            note: "Nouveau 2e record absolu !",
            removable: true,
            localLegend: false
        ))
        #expect(summary.lines[1].figures == ["0,37 km", "2:11", "5:54 /km"])
        #expect(summary.lines[1].note == "Record personnel")
        #expect(summary.lines[2].note == "3e meilleur temps")
    }

    @Test func aFirstPassSaysSo() {
        let line = ActivityResultsSummary.line(SegmentEffortResult.fixture(medal: .gold, isFirstPass: true), sport: .run)

        #expect(line.note == "Record personnel · 1er passage")
    }

    @Test func titlesNameTheDistance() {
        let titles = [400, 1_000, 1_500, 21_097.5, 42_195, 160_000].map {
            ActivityResultsSummary.line(BestEffortResult.fixture(distanceM: $0), sport: .run).title
        }

        #expect(titles == ["400 M", "1 KM", "1,5 KM", "SEMI-MARATHON", "MARATHON", "160 KM"])
        #expect(ActivityResultsSummary.line(BestEffortResult.fixture(distanceM: 1_500), sport: .swim).title == "1500 M")
    }

    /// km/h by bike, /km on foot, /100 m in the water; hours past an hour.
    @Test func paceFollowsTheSport() {
        let ride = ActivityResultsSummary.line(BestEffortResult.fixture(distanceM: 40_000, seconds: 3_723), sport: .ride)
        let swim = ActivityResultsSummary.line(BestEffortResult.fixture(distanceM: 100, seconds: 105), sport: .swim)

        #expect(ride.figures == ["1:02:03", "38,7 km/h"])
        #expect(swim.figures == ["1:45", "1:45 /100 m"])
    }

    /// A Best effort without a Medal has no phrase; the Local Legend wears the crown.
    @Test func unmedalledLinesHaveNoPhrase() {
        #expect(ActivityResultsSummary.line(BestEffortResult.fixture(), sport: .run).note == nil)
        #expect(ActivityResultsSummary.line(SegmentEffortResult.fixture(localLegend: true), sport: .run).localLegend)
    }

    /// On the map, each medalled Segment gets its ribbon at its start with the phrase and its
    /// name; a Segment without a Medal has no badge.
    @Test func onlyMedalledSegmentsGetARibbonOnTheMap() {
        let marks = SegmentMedalMark.marks(results(efforts: [
            .fixture(id: "a", name: "Reference Albigny", medal: .gold, isFirstPass: true),
            .fixture(id: "b", name: "Sans médaille"),
            .fixture(id: "c", name: "Petit Port", medal: .bronze),
        ]))

        #expect(marks.map(\.name) == ["Reference Albigny", "Petit Port"])
        #expect(marks.map(\.phrase) == ["Record personnel", "3e meilleur temps"])
        #expect(marks[0].coordinate == Coordinate(latitude: 45.9, longitude: 6.13))
        #expect(SegmentMedalMark.marks(nil).isEmpty)
    }
}
