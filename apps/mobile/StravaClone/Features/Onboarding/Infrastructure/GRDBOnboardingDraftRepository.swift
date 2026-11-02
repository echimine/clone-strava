import Foundation
import GRDB

/// GRDB adapter of `OnboardingDraftRepository` (ADR-035 §5, migration `onboarding_draft_v1`):
/// the one row of `onboarding_draft`.
struct GRDBOnboardingDraftRepository: OnboardingDraftRepository {
    let database: AppDatabase

    func load() async throws -> OnboardingDraft? {
        try await database.writer.read { db in
            try OnboardingDraftRow.fetchOne(db)?.draft
        }
    }

    func save(_ draft: OnboardingDraft) async throws {
        try await database.writer.write { db in
            try OnboardingDraftRow(draft).save(db)
        }
    }

    func delete() async throws {
        _ = try await database.writer.write { db in
            try OnboardingDraftRow.deleteAll(db)
        }
    }
}

// MARK: - Row

private struct OnboardingDraftRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "onboarding_draft"
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }

    var id = 1
    var step: String
    var firstName: String
    var lastName: String
    var birthDate: String?
    var gender: String?
    var sportCodes: [String]
    var goals: [String]
    var level: String?

    init(_ draft: OnboardingDraft) {
        let answers = draft.answers
        step = draft.step.rawValue
        firstName = answers.firstName
        lastName = answers.lastName
        birthDate = answers.birthDate?.iso
        gender = answers.gender?.rawValue
        sportCodes = answers.sports.map(\.code)
        goals = answers.goals.map(\.rawValue)
        level = answers.level?.rawValue
    }

    /// Values this version does not know (a later one wrote them) are dropped, not the draft.
    var draft: OnboardingDraft {
        var answers = OnboardingAnswers()
        answers.firstName = firstName
        answers.lastName = lastName
        answers.birthDate = birthDate.flatMap(CalendarDay.init(iso:))
        answers.gender = gender.flatMap(Gender.init(rawValue:))
        answers.sports = sportCodes.map(SportType.init(code:)).filter(SportType.active.contains)
        answers.goals = goals.compactMap(Goal.init(rawValue:))
        answers.level = level.flatMap(AthleteLevel.init(rawValue:))
        return OnboardingDraft(answers: answers, step: OnboardingStep(rawValue: step) ?? .name)
    }
}
