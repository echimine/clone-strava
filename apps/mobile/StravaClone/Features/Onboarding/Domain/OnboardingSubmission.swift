import Foundation

/// The Onboarding answers as `PUT /v1/me/onboarding-answers` takes them (ADR-035 §5): every
/// question answered, names trimmed. Built from the draft when it is sent.
struct OnboardingSubmission: Equatable, Sendable {
    let firstName: String
    let lastName: String
    let birthDate: CalendarDay
    let gender: Gender
    let sports: [SportType]
    let goals: [Goal]
    let level: AthleteLevel

    /// `nil` while a required answer is missing: such a draft is never sent.
    init?(_ answers: OnboardingAnswers) {
        let firstName = answers.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastName = answers.lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !firstName.isEmpty, !lastName.isEmpty, let birthDate = answers.birthDate,
              let gender = answers.gender, !answers.sports.isEmpty, let level = answers.level
        else { return nil }
        self.firstName = firstName
        self.lastName = lastName
        self.birthDate = birthDate
        self.gender = gender
        sports = answers.sports
        goals = answers.goals
        self.level = level
    }
}

/// Why the answers did not reach the server.
enum OnboardingSubmissionError: Error, Equatable, Sendable {
    /// No network, timeout, transport failure, `5xx`: tried again later.
    case unavailable(String)
    case unauthorized
    /// Any other `4xx`: the answers are dropped.
    case refused(status: Int)
}

/// The server side of the Onboarding answers (ADR-035 §5): `204` whatever it fills.
protocol OnboardingAnswersServer: Sendable {
    func submit(_ submission: OnboardingSubmission) async throws(OnboardingSubmissionError)
}

/// The `submit_onboarding_answers` operation waiting in `sync_operation` (ADR-035 §5): no
/// payload, the sender reads the draft.
struct PendingOnboardingSubmission: Equatable, Sendable {
    let attempts: Int
    let nextAttemptAt: Date
}

/// Persistence port of that operation: one at most.
protocol OnboardingSubmissionQueue: Sendable {
    func pending() async throws -> PendingOnboardingSubmission?
    /// Queues the operation, due at `date`; one already queued is kept as it is.
    func enqueue(at date: Date) async throws
    func postpone(until date: Date, error: String) async throws
    func remove() async throws
}
