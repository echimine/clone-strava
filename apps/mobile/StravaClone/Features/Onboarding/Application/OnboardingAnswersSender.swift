import Foundation
import os

/// Sends the Onboarding answers once a session exists (ADR-035 §5, amending ADR-008): a
/// `submit_onboarding_answers` operation of `sync_operation`, without payload, that reads the
/// draft when it is sent.
/// - right after sign-in on the Onboarding path (`submit`), then on the queue's triggers
///   (`send`, from `SyncQueueCoordinator`: foreground, network back, background refresh);
/// - no network, timeout or `5xx`: tried again after a capped exponential backoff (2 s to
///   300 s), with no attempt limit;
/// - `401`: the session is refreshed, then the answers are sent again once;
/// - `204`, or any other `4xx` (logged, nothing shown): the draft and the operation are deleted.
/// Nobody waits for it: the flow goes on at once.
@MainActor
final class OnboardingAnswersSender {
    private static let logger = Logger(subsystem: "fr.echimine.stravaclone", category: "onboarding")

    private let server: any OnboardingAnswersServer
    private let drafts: any OnboardingDraftRepository
    private let queue: any OnboardingSubmissionQueue
    private let sessionRefresher: any SessionRefreshing
    private let backoff: RetryBackoff
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void

    private var sending: Task<Void, Never>?
    /// A trigger arrived during a pass: one more pass runs before `send` returns.
    private var rerun = false
    private var rerunIgnoringBackoff = false
    /// Sends again when the postponed operation is due, while the app runs.
    private var wakeUp: Task<Void, Never>?
    /// Bumped by sign-out: a pass started before must not write anything.
    private var generation = 0

    init(
        server: any OnboardingAnswersServer,
        drafts: any OnboardingDraftRepository,
        queue: any OnboardingSubmissionQueue,
        sessionRefresher: any SessionRefreshing,
        backoff: RetryBackoff = RetryBackoff(initialDelay: .seconds(2), maxDelay: .seconds(300)),
        now: @escaping @Sendable () -> Date = Date.init,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.server = server
        self.drafts = drafts
        self.queue = queue
        self.sessionRefresher = sessionRefresher
        self.backoff = backoff
        self.now = now
        self.sleep = sleep
    }

    /// Right after sign-in on the Onboarding path: queued first, so an app killed during the
    /// request still sends later, then sent at once.
    func submit() async {
        do {
            try await queue.enqueue(at: now())
        } catch {
            Self.logger.error("Could not queue the Onboarding answers: \(error)")
            return
        }
        await send()
    }

    /// Sends the queued answers if they are due, or whenever when `ignoringBackoff` (the network
    /// is back, the app is in the foreground again). Joins the pass already running.
    func send(ignoringBackoff: Bool = false) async {
        if let sending {
            rerun = true
            rerunIgnoringBackoff = rerunIgnoringBackoff || ignoringBackoff
            await sending.value
            return
        }
        let generation = generation
        let task = Task { await self.run(ignoringBackoff: ignoringBackoff, generation: generation) }
        sending = task
        await task.value
    }

    /// iOS takes the background time back (ADR-031 §14): the pass in flight stops, the
    /// operation stays queued, and the next trigger sends.
    func cancelPass() {
        wakeUp?.cancel()
        wakeUp = nil
        sending?.cancel()
    }

    /// Sign-out: the draft and the operation are deleted; a pass in flight writes nothing more.
    func clear() async {
        generation += 1
        wakeUp?.cancel()
        wakeUp = nil
        sending?.cancel()
        sending = nil
        rerun = false
        rerunIgnoringBackoff = false
        try? await queue.remove()
        try? await drafts.delete()
    }

    private func run(ignoringBackoff: Bool, generation: Int) async {
        var ignoringBackoff = ignoringBackoff
        repeat {
            rerun = false
            await sendPending(ignoringBackoff: ignoringBackoff, generation: generation)
            ignoringBackoff = rerunIgnoringBackoff
            rerunIgnoringBackoff = false
        } while rerun && self.generation == generation && !Task.isCancelled
        guard self.generation == generation else { return }
        sending = nil
        guard !Task.isCancelled else { return }
        await scheduleWakeUp(generation: generation)
    }

    private func sendPending(ignoringBackoff: Bool, generation: Int) async {
        guard let pending = try? await queue.pending(),
              ignoringBackoff || SyncQueueSchedule.isDue(pending.nextAttemptAt, at: now())
        else { return }
        guard let submission = await submission() else {
            Self.logger.error("No complete Onboarding answers to send: the operation is dropped")
            try? await queue.remove()
            return
        }
        let result = await attempt(submission)
        guard self.generation == generation else { return }
        switch result {
        case .success:
            await done()
        case .failure(.refused(let status)):
            Self.logger.error("The server refused the Onboarding answers (HTTP \(status)): they are dropped")
            await done()
        case .failure(let error):
            let delay = backoff.delay(beforeRetry: pending.attempts)
            try? await queue.postpone(until: now().addingTimeInterval(delay.timeInterval), error: "\(error)")
        }
    }

    private func submission() async -> OnboardingSubmission? {
        guard let draft = try? await drafts.load() else { return nil }
        return OnboardingSubmission(draft.answers)
    }

    private func done() async {
        try? await drafts.delete()
        try? await queue.remove()
    }

    /// The request, sent once more after a `401` if the session could be refreshed.
    private func attempt(_ submission: OnboardingSubmission) async -> Result<Void, OnboardingSubmissionError> {
        let result = await request(submission)
        guard case .failure(.unauthorized) = result, await sessionRefresher.refresh() else { return result }
        return await request(submission)
    }

    private func request(_ submission: OnboardingSubmission) async -> Result<Void, OnboardingSubmissionError> {
        do throws(OnboardingSubmissionError) {
            try await server.submit(submission)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    private func scheduleWakeUp(generation: Int) async {
        wakeUp?.cancel()
        wakeUp = nil
        guard let next = try? await queue.pending()?.nextAttemptAt, self.generation == generation else { return }
        let delay = max(0, next.timeIntervalSince(now()))
        let sleep = sleep
        wakeUp = Task { [weak self] in
            guard (try? await sleep(.seconds(delay))) != nil, !Task.isCancelled else { return }
            await self?.send()
        }
    }
}
