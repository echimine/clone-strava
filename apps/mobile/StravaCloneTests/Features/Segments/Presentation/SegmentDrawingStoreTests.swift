import Foundation
import Testing
@testable import StravaClone

/// Drawing a Segment in the Itinerary editor (ADR-039 §15): live figures through `preview`,
/// « Continuer » greyed out with a message while a rule fails, « Connexion requise » offline.
@MainActor
struct SegmentDrawingStoreTests {
    /// Meters per degree of latitude on the app's sphere.
    private static let metersPerDegree = 6_371_000 * Double.pi / 180

    /// A straight line north from Annecy, `meters` long.
    private func north(_ meters: Double, from start: Double = 0) -> [Coordinate] {
        [
            Coordinate(latitude: 45.9 + start / Self.metersPerDegree, longitude: 6.12),
            Coordinate(latitude: 45.9 + (start + meters) / Self.metersPerDegree, longitude: 6.12),
        ]
    }

    private func settled(_ path: [Coordinate]) -> SegmentDrawing {
        let length = zip(path, path.dropFirst()).reduce(Distance.zero) { $0 + $1.0.distance(to: $1.1) }
        return SegmentDrawing(path: .settled(path), distance: length)
    }

    private func makeStore(
        sport: SegmentSport = .run,
        repository: FakeSegmentCreationRepository = FakeSegmentCreationRepository(),
        isOnline: @escaping @MainActor () -> Bool = { true }
    ) -> SegmentDrawingStore {
        SegmentDrawingStore(sport: sport, preview: PreviewSegment(repository: repository), isOnline: isOnline, debounce: .zero)
    }

    @Test func asksForAStartAndAFinishFirst() {
        let store = makeStore()
        store.update(.empty)
        #expect(!store.canContinue)
        #expect(store.blocker == "Place un départ et une arrivée sur la carte.")
    }

    @Test func greysOutContinueWhileTooShortForTheSport() async {
        let run = makeStore(sport: .run)
        run.update(settled(north(150)))
        #expect(!run.canContinue)
        #expect(run.blocker == "Trop court : au moins 200 m.")

        let ride = makeStore(sport: .ride)
        ride.update(settled(north(400)))
        #expect(ride.blocker == "Trop court : au moins 500 m à vélo.")
        ride.update(settled(north(600)))
        #expect(ride.blocker == nil)
        #expect(ride.canContinue)
    }

    @Test func refusesALoop() {
        let store = makeStore()
        let start = Coordinate(latitude: 45.9, longitude: 6.12)
        let loop = [start, Coordinate(latitude: 45.904, longitude: 6.12), Coordinate(latitude: 45.904, longitude: 6.124), Coordinate(latitude: 45.9003, longitude: 6.12)]
        store.update(settled(loop))
        #expect(store.blocker == "Le départ et l'arrivée doivent être à plus de 100 m l'un de l'autre.")
    }

    @Test func refusesMoreThan50Kilometres() {
        let store = makeStore(sport: .ride)
        store.update(settled(north(50_500)))
        #expect(store.blocker == "Trop long : 50 km au plus.")
    }

    @Test func showsTheFiguresTheServerMeasuredForTheSettledPath() async {
        let repository = FakeSegmentCreationRepository()
        let store = makeStore(repository: repository)
        let path = north(1_000)

        store.update(settled(path))
        await store.settle()

        #expect(await repository.previews == [path])
        #expect(store.distanceText == "1,00 km")
        #expect(store.elevationGainText == "80 m")
        #expect(store.averageGradeText == "8,0 %")
    }

    @Test func dropsTheFiguresOfAPathThatChangedSince() async {
        let repository = FakeSegmentCreationRepository()
        await repository.hold()
        let store = makeStore(repository: repository)

        store.update(settled(north(1_000)))
        await repository.waitForPreviews(1)
        store.update(SegmentDrawing(path: .changing, distance: Distance(meters: 1_200)))
        await repository.release()
        await store.settle()

        #expect(store.elevationGainText == "–")
        #expect(store.distanceText == "1,20 km")
    }

    @Test func continueOpensThePreviewOfTheMeasuredPath() async {
        let repository = FakeSegmentCreationRepository()
        let store = makeStore(repository: repository)
        let path = north(1_000)
        store.update(settled(path))
        await store.settle()

        await store.continueTapped()

        #expect(store.next == SegmentCandidate(sport: .run, points: path, preview: FakeSegmentCreationRepository.preview(of: path)))
        #expect(await repository.previews.count == 1)
    }

    /// Hors ligne : the button stays active and says why it does nothing.
    @Test func offlineContinueSaysConnectionRequired() async {
        let store = makeStore(isOnline: { false })
        store.update(settled(north(1_000)))
        await store.settle()
        #expect(store.canContinue)

        await store.continueTapped()

        #expect(store.next == nil)
        #expect(store.message == "Connexion requise")
    }

    @Test func continueMeasuresAgainWhenTheLivePreviewFailed() async {
        let repository = FakeSegmentCreationRepository()
        await repository.answerPreviews { _ in .failure(.server) }
        let store = makeStore(repository: repository)
        let path = north(1_000)
        store.update(settled(path))
        await store.settle()
        #expect(store.elevationGainText == "–")

        await repository.answerPreviews { .success(FakeSegmentCreationRepository.preview(of: $0)) }
        await store.continueTapped()

        #expect(store.next == SegmentCandidate(sport: .run, points: path, preview: FakeSegmentCreationRepository.preview(of: path)))
    }

    @Test func aRuleOnlyTheServerSawKeepsTheDrawing() async {
        let repository = FakeSegmentCreationRepository()
        await repository.answerPreviews { .success(FakeSegmentCreationRepository.preview(of: $0, violations: [.loop])) }
        let store = makeStore(repository: repository)
        store.update(settled(north(1_000)))
        await store.settle()

        await store.continueTapped()

        #expect(store.next == nil)
        #expect(store.message == "Le départ et l'arrivée doivent être à plus de 100 m l'un de l'autre.")
    }
}
