import Foundation
import Testing
@testable import StravaClone

@MainActor
struct AthleteStatisticsStoreTests {
    private func makeStore(
        _ repository: FakeAthleteStatsRepository,
        sports: [SportType] = [.ride, .run]
    ) -> AthleteStatisticsStore {
        AthleteStatisticsStore(
            request: AthleteStatisticsRequest(athleteId: "athlete-1", sports: sports),
            loadStats: LoadAthleteStats(repository: repository)
        )
    }

    @Test func opensOnTheAthletesFirstSport() async {
        let repository = FakeAthleteStatsRepository()
        repository.results[.ride] = .success(.fixture(sport: .ride))
        let store = makeStore(repository)

        await store.load()
        await store.load()

        #expect(store.sports == [.ride, .run])
        #expect(store.sport == .ride)
        #expect(store.stats == .fixture(sport: .ride))
        #expect(store.phase == .loaded)
        #expect(repository.calls.map(\.athleteId) == ["athlete-1"])
        #expect(repository.calls.map(\.sport) == [.ride])
    }

    @Test func withoutPracticedSportsItOffersTheActiveSports() {
        let store = makeStore(FakeAthleteStatsRepository(), sports: [])

        #expect(store.sports == SportType.active)
        #expect(store.sport == .run)
    }

    @Test func choosingASportReloadsTheStatisticsForIt() async {
        let repository = FakeAthleteStatsRepository()
        repository.results[.ride] = .success(.fixture(sport: .ride))
        repository.results[.run] = .success(.fixture(sport: .run, yearToDateCount: 7))
        let store = makeStore(repository)
        await store.load()

        await store.select(.run)

        #expect(store.sport == .run)
        #expect(store.stats == .fixture(sport: .run, yearToDateCount: 7))
        #expect(repository.calls.map(\.sport) == [.ride, .run])
    }

    @Test func aFailureSaysSoAndCanBeRetried() async {
        let repository = FakeAthleteStatsRepository()
        repository.results[.ride] = .failure(.offline)
        let store = makeStore(repository)

        await store.load()
        #expect(store.phase == .failed(message: "Vous êtes hors ligne."))
        #expect(store.stats == nil)

        repository.results[.ride] = .success(.fixture(sport: .ride))
        await store.retry()
        #expect(store.phase == .loaded)
        #expect(store.stats == .fixture(sport: .ride))
    }
}

struct AthleteStatisticsSectionsTests {
    @Test func theThreeSectionsInOrder() {
        let sections = AthleteStatisticsSection.sections(for: .fixture(sport: .run))

        #expect(sections.map(\.title) == ["ACTIVITÉ", "DEPUIS LE DÉBUT DE L'ANNÉE", "DE TOUT TEMPS"])
        #expect(sections[0].rows == [
            .init(label: "Courses par semaine", value: "1,5"),
            .init(label: "Temps par semaine", value: "1 h 00 min"),
            .init(label: "Distance par semaine", value: "12,00 km"),
        ])
        #expect(sections[1].rows == [
            .init(label: "Courses", value: "40"),
            .init(label: "Temps", value: "25 h 00 min"),
            .init(label: "Distance", value: "412,00 km"),
            .init(label: "Dénivelé", value: "3\u{202F}000 m"),
        ])
        #expect(sections[2].rows == [
            .init(label: "Courses", value: "80"),
            .init(label: "Distance", value: "900,00 km"),
            .init(label: "Dénivelé", value: "7\u{202F}000 m"),
        ])
    }

    @Test(arguments: [
        (SportType?.some(.run), "Courses"),
        (.some(.ride), "Sorties à vélo"),
        (.some(.swim), "Séances de natation"),
        (.some(.walk), "Marches"),
        (.some(.hike), "Randonnées"),
        (.some(.other("yoga")), "Activités"),
        (nil, "Activités"),
    ])
    func theOutingsLabelFollowsTheSport(sport: SportType?, label: String) {
        let sections = AthleteStatisticsSection.sections(for: .fixture(sport: sport))

        #expect(sections[1].rows.first?.label == label)
        #expect(sections[2].rows.first?.label == label)
        #expect(sections[0].rows.first?.label == "\(label) par semaine")
    }

    @Test func swimmingHasNoElevation() {
        let sections = AthleteStatisticsSection.sections(for: .fixture(sport: .swim))

        #expect(sections.flatMap(\.rows).allSatisfy { $0.label != "Dénivelé" })
    }
}
