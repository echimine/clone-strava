import Foundation

/// The screens of the Onboarding, in order (ADR-035 §1): the six questions, then "Voici ce qui
/// vous attend", the personalised loading, and the account screen.
enum OnboardingStep: String, CaseIterable, Sendable {
    case name, birthDate, gender, sports, goals, level
    case showcase, personalizing, account
}

/// The answers and the screen reached (`onboarding_draft`, ADR-035 §5): the only local copy of
/// the answers, so an interrupted Onboarding resumes where it stopped.
struct OnboardingDraft: Equatable, Sendable {
    var answers = OnboardingAnswers()
    var step = OnboardingStep.name
}

/// Persistence port of the draft: one at most.
protocol OnboardingDraftRepository: Sendable {
    func load() async throws -> OnboardingDraft?
    /// Replaces the draft.
    func save(_ draft: OnboardingDraft) async throws
    /// The next Onboarding starts afresh.
    func delete() async throws
}
