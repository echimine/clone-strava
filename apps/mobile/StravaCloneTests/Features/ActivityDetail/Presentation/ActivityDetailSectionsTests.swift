import Foundation
import Testing
@testable import StravaClone

/// Which parts of the detail show (ADR-036 §9): the map with a route, and the splits and
/// charts (sections 8 to 10) only with an analysis that has splits; heart rate only with it.
struct ActivityDetailSectionsTests {
    private let split = ActivitySplit(distance: Distance(meters: 1_000), movingTime: .seconds(300), elevationDiff: 2, avgHeartRate: nil)

    private func series(heartRate: [Int]?) -> ActivitySeries {
        ActivitySeries(distanceM: [0, 1_000], speedMs: [3, 3.5], altitudeM: [100, 110], heartRateBpm: heartRate)
    }

    @Test func aManualActivityShowsNoMapNoSplitsAndNoChart() {
        let detail = ActivityDetail.fixture(route: nil, source: .manual, analysis: ActivityAnalysis(splits: [], series: nil))

        let sections = ActivityDetailSections(detail: detail)

        #expect(!sections.showsMap)
        #expect(sections.splits == nil)
        #expect(sections.speedChart == nil)
        #expect(sections.heartRateChart == nil)
    }

    /// Not computed yet: the map shows, the analysis sections do not.
    @Test func anAnalysisNotComputedYetHidesTheAnalysisSections() {
        let sections = ActivityDetailSections(detail: .fixture(analysis: nil))

        #expect(sections.showsMap)
        #expect(sections.splits == nil)
        #expect(sections.speedChart == nil)
        #expect(sections.heartRateChart == nil)
    }

    @Test func anAnalysisWithHeartRateShowsEverySection() {
        let detail = ActivityDetail.fixture(analysis: ActivityAnalysis(splits: [split], series: series(heartRate: [140, 150])))

        let sections = ActivityDetailSections(detail: detail)

        #expect(sections.splits?.rows.count == 1)
        #expect(sections.speedChart != nil)
        #expect(sections.heartRateChart?.points.map(\.value) == [140, 150])
    }

    @Test func heartRateIsHiddenWithoutIt() {
        let detail = ActivityDetail.fixture(analysis: ActivityAnalysis(splits: [split], series: series(heartRate: nil)))

        let sections = ActivityDetailSections(detail: detail)

        #expect(sections.splits != nil)
        #expect(sections.speedChart != nil)
        #expect(sections.heartRateChart == nil)
    }

    /// The source line (ADR-036 §9); the API does not give the import format yet.
    @Test func theSourceLineSaysHowTheActivityCameIn() {
        #expect(ActivityAnalysisMessages.source(.recorded) == "Enregistré avec Nervo")
        #expect(ActivityAnalysisMessages.source(.imported) == "Importé")
        #expect(ActivityAnalysisMessages.source(.manual) == "Saisie manuelle")
    }
}
