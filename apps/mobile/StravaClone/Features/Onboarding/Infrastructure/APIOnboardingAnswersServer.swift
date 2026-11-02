import Foundation

/// `APIClient` adapter of `OnboardingAnswersServer`: `PUT /v1/me/onboarding-answers`
/// (ADR-035 §5), on the type generated from openapi.json (ADR-026 §5).
struct APIOnboardingAnswersServer: OnboardingAnswersServer {
    private typealias Request = Components.Schemas.OnboardingAnswersRequestDto

    let apiClient: APIClient

    func submit(_ submission: OnboardingSubmission) async throws(OnboardingSubmissionError) {
        let body = Request(
            firstName: submission.firstName,
            lastName: submission.lastName,
            birthDate: submission.birthDate.iso,
            gender: Request.genderPayload(rawValue: submission.gender.rawValue) ?? .undisclosed,
            sportCodes: submission.sports.map(\.code),
            goals: submission.goals.compactMap { Request.goalsPayloadPayload(rawValue: $0.rawValue) },
            level: Request.levelPayload(rawValue: submission.level.rawValue) ?? .beginner
        )
        do {
            let _: NoContent = try await apiClient.send(method: "PUT", path: "/v1/me/onboarding-answers", body: body)
        } catch {
            throw Self.map(error)
        }
    }

    private static func map(_ error: APIError) -> OnboardingSubmissionError {
        switch error {
        case .unauthorized: .unauthorized
        case .http(let status, _) where (400 ..< 500).contains(status): .refused(status: status)
        case .http(let status, _): .unavailable("HTTP \(status)")
        case .offline: .unavailable("offline")
        case .transport(let message): .unavailable(message)
        case .decoding: .unavailable("decoding")
        }
    }
}
