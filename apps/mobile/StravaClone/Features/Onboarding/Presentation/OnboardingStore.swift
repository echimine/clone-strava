import Foundation
import Observation

/// The Onboarding (ADR-035 §1): one question per screen, then "Voici ce qui vous attend", the
/// personalised loading and the account screen. The draft is written at each step (§5), and a
/// new store resumes from it.
///
/// Opened by "Se connecter" on an account it has just created (`finishWithSession`), the
/// Onboarding starts at its first question, saved answers kept, and "Créer mon compte" ends it
/// without the account screen: the session exists already.
///
/// Each screen up to the personalised loading sends `onboarding_step_viewed`, the first one
/// viewed after resuming a draft with `resumed`, whatever the screen it resumed on. "Créer mon
/// compte" sends `onboarding_completed` once per Onboarding (ADR-035 §8): sports, goals and level
/// only.
@Observable
@MainActor
final class OnboardingStore {
    var answers = OnboardingAnswers()
    private(set) var step = OnboardingStep.name

    @ObservationIgnored private let drafts: any OnboardingDraftRepository
    @ObservationIgnored private let analytics: any AnalyticsClient
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let finishWithSession: (@MainActor () -> Void)?
    /// A draft was resumed and no Onboarding screen has been viewed since.
    @ObservationIgnored private var isResumePending = false
    /// `onboarding_completed` is sent: reaching the account screen, even in an earlier launch.
    @ObservationIgnored private var isCompleted = false

    init(
        drafts: any OnboardingDraftRepository,
        analytics: any AnalyticsClient = NoAnalyticsClient(),
        now: @escaping () -> Date = Date.init,
        finishWithSession: (@MainActor () -> Void)? = nil
    ) {
        self.drafts = drafts
        self.analytics = analytics
        self.now = now
        self.finishWithSession = finishWithSession
    }

    /// Resumes the saved draft, if any; the first screen viewed is marked as resumed.
    func load() async {
        if let draft = try? await drafts.load() {
            answers = draft.answers
            isCompleted = draft.step == .account
            if finishWithSession == nil {
                step = draft.step
            }
            isResumePending = true
        }
        stepViewed()
    }

    /// Whether the current screen lets the person go on.
    var canContinue: Bool {
        switch step {
        case .name: answers.hasName
        case .birthDate: answers.isOldEnough(on: today())
        case .gender: answers.gender != nil
        case .sports: !answers.sports.isEmpty
        case .goals: true
        case .level: answers.level != nil
        case .showcase, .personalizing, .account: true
        }
    }

    /// The birth date field unfolds its wheel set on 30 years ago, so most people scroll little.
    func unfoldBirthDateWheel() {
        guard answers.birthDate == nil else { return }
        let today = today()
        answers.birthDate = CalendarDay(year: today.year - 30, month: today.month, day: today.day)
    }

    /// The goals are optional: without one, the button skips the question.
    var continueTitle: String {
        step == .goals && answers.goals.isEmpty ? "Passer" : "Continuer"
    }

    /// Picks a goal, or unpicks it.
    func toggle(_ goal: Goal) {
        if let index = answers.goals.firstIndex(of: goal) {
            answers.goals.remove(at: index)
        } else {
            answers.goals.append(goal)
        }
    }

    /// The day the minimum age is checked on: the server's, in UTC.
    private func today() -> CalendarDay {
        .utc(now())
    }

    /// The active sports (`sport_type.is_active`): never a sport that cannot be recorded.
    let sportChoices = SportType.active

    /// Picks a sport after the others, or unpicks it.
    func toggle(_ sport: SportType) {
        if let index = answers.sports.firstIndex(of: sport) {
            answers.sports.remove(at: index)
        } else {
            answers.sports.append(sport)
        }
    }

    /// A birth date is set but under the minimum age: the red line under the field.
    var isTooYoung: Bool {
        answers.birthDate != nil && !answers.isOldEnough(on: today())
    }

    /// The next screen, once the current one is valid.
    func next() async {
        if step == .personalizing {
            completed()
            if let finishWithSession {
                await saveDraft()
                finishWithSession()
                return
            }
        }
        guard canContinue,
              let index = OnboardingStep.allCases.firstIndex(of: step),
              index + 1 < OnboardingStep.allCases.count
        else { return }
        step = OnboardingStep.allCases[index + 1]
        stepViewed()
        await saveDraft()
    }

    /// The round back button, absent on the first screen.
    var canGoBack: Bool { step != OnboardingStep.allCases.first }

    /// The previous screen, answers kept.
    func back() async {
        guard let index = OnboardingStep.allCases.firstIndex(of: step), index > 0 else { return }
        step = OnboardingStep.allCases[index - 1]
        stepViewed()
        await saveDraft()
    }

    /// The first screen's back button, to the Welcome (decision on #128): the draft keeps what
    /// was typed, so the next "Créer un compte" resumes here.
    func leave() async {
        await saveDraft()
    }

    /// The first name without surrounding spaces, for the greetings.
    var firstName: String { answers.firstName.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The account's name if the code creates it (ADR-035 §2): "Prénom Nom".
    var accountName: String {
        "\(firstName) \(answers.lastName.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    /// The account screen sends `auth_screen_viewed` instead.
    private func stepViewed() {
        guard let screen = AnalyticsEvent.OnboardingScreen(step) else { return }
        analytics.capture(.onboardingStepViewed(step: screen, resumed: isResumePending))
        isResumePending = false
    }

    /// "Créer mon compte", the first time: never the name, the birth date or the gender
    /// (ADR-035 §8).
    private func completed() {
        guard !isCompleted else { return }
        isCompleted = true
        analytics.capture(.onboardingCompleted(
            sportCodes: answers.sports.map(\.code),
            goals: answers.goals.map(\.rawValue),
            level: answers.level?.rawValue ?? ""
        ))
    }

    /// Writes the answers and the screen reached. A failure is not shown: the Onboarding goes
    /// on, only its resumption is lost.
    private func saveDraft() async {
        try? await drafts.save(OnboardingDraft(answers: answers, step: step))
    }
}

private extension AnalyticsEvent.OnboardingScreen {
    /// `nil` for the account screen.
    init?(_ step: OnboardingStep) {
        switch step {
        case .name: self = .name
        case .birthDate: self = .birthdate
        case .gender: self = .gender
        case .sports: self = .sports
        case .goals: self = .goals
        case .level: self = .level
        case .showcase: self = .showcase
        case .personalizing: self = .personalizing
        case .account: return nil
        }
    }
}
