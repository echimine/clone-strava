import Foundation
@testable import StravaClone

/// Hand-written `SegmentCreationRepository` (ADR-025 §3): records every call, previews any
/// path as a steady 8 % climb, and creates with `createAnswer`. `hold()` suspends previews
/// until `release()`, to observe in-flight states and races.
actor FakeSegmentCreationRepository: SegmentCreationRepository {
    struct Creation: Equatable, Sendable {
        let sport: SegmentSport
        let name: String
        let points: [Coordinate]
    }

    private(set) var previews: [[Coordinate]] = []
    private(set) var creations: [Creation] = []
    private var previewAnswer: @Sendable ([Coordinate]) -> Result<SegmentPreview, SegmentCreationError> = {
        .success(FakeSegmentCreationRepository.preview(of: $0))
    }
    private var createAnswer: Result<SegmentRef, SegmentCreationError> = .success(SegmentRef(id: "seg-1", name: "Créé"))
    private var isHolding = false
    private var held: [CheckedContinuation<Void, Never>] = []

    /// A steady 8 % climb along the path: 80 m of gain per km.
    static func preview(
        of points: [Coordinate],
        duplicate: SegmentRef? = nil,
        quotaLeft: Int = 10,
        violations: [SegmentRuleViolation] = []
    ) -> SegmentPreview {
        let length = zip(points, points.dropFirst()).reduce(Distance.zero) { $0 + $1.0.distance(to: $1.1) }
        return SegmentPreview(
            figures: SegmentFigures(
                distance: length,
                elevationGain: length.meters * 0.08,
                averageGrade: 8,
                maxGrade: 9.5,
                lowestAltitude: 500,
                highestAltitude: 500 + length.meters * 0.08,
                climbCategory: length.meters * 8 >= 8_000 ? .cat4 : nil
            ),
            track: points,
            altitudes: points.indices.map { 500 + Double($0) },
            violations: violations,
            duplicate: duplicate,
            quotaLeft: quotaLeft
        )
    }

    func answerPreviews(with answer: @escaping @Sendable ([Coordinate]) -> Result<SegmentPreview, SegmentCreationError>) {
        previewAnswer = answer
    }

    func answerCreation(with answer: Result<SegmentRef, SegmentCreationError>) {
        createAnswer = answer
    }

    func hold() {
        isHolding = true
    }

    func release() {
        isHolding = false
        let continuations = held
        held = []
        continuations.forEach { $0.resume() }
    }

    func waitForPreviews(_ count: Int) async {
        while previews.count < count {
            await Task.yield()
        }
    }

    func preview(sport: SegmentSport, points: [Coordinate]) async throws(SegmentCreationError) -> SegmentPreview {
        previews.append(points)
        if isHolding {
            await withCheckedContinuation { held.append($0) }
        }
        return try previewAnswer(points).get()
    }

    func create(sport: SegmentSport, name: String, points: [Coordinate]) async throws(SegmentCreationError) -> SegmentRef {
        creations.append(Creation(sport: sport, name: name, points: points))
        return try createAnswer.get()
    }
}

/// Hand-written `StarredSegmentsRepository`: answers pages by cursor from `pages`.
actor FakeStarredSegmentsRepository: StarredSegmentsRepository {
    private var pages: [String?: StarredSegmentsPage] = [:]
    private var error: StarredSegmentsError?
    private(set) var requestedCursors: [String?] = []

    func serve(_ page: StarredSegmentsPage, after cursor: String? = nil) {
        pages[cursor] = page
    }

    func fail(with error: StarredSegmentsError?) {
        self.error = error
    }

    func page(after cursor: String?) async throws(StarredSegmentsError) -> StarredSegmentsPage {
        requestedCursors.append(cursor)
        if let error { throw error }
        return pages[cursor] ?? StarredSegmentsPage(items: [], nextCursor: nil)
    }
}

extension StarredSegment {
    static func fixture(_ number: Int, sport: SegmentSport = .ride, best: Duration? = nil) -> StarredSegment {
        StarredSegment(
            id: "segment-\(number)",
            sport: sport,
            name: "Segment \(number)",
            isVerified: false,
            distance: Distance(meters: 1_000 * Double(number)),
            averageGrade: 5.2,
            climbCategory: nil,
            myBestTime: best
        )
    }
}
