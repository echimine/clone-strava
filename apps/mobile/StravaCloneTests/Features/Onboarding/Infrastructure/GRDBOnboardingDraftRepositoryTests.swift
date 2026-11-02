import Foundation
import Testing
@testable import StravaClone

struct GRDBOnboardingDraftRepositoryTests {
    @Test func deletingTheDraftStartsTheOnboardingAfresh() async throws {
        let repository = GRDBOnboardingDraftRepository(database: try AppDatabase.inMemory())
        var draft = OnboardingDraft()
        draft.answers.firstName = "Camille"
        draft.step = .gender
        try await repository.save(draft)

        try await repository.delete()

        #expect(try await repository.load() == nil)
    }
}
