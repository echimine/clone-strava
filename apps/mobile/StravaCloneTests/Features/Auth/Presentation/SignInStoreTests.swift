import Foundation
import Testing
@testable import StravaClone

/// The account screen and the Sign-in code screen (ADR-035 §1, §2), through `SignInStore`
/// over a fake `AuthRepository`.
@MainActor
struct SignInStoreTests {
    struct Harness {
        let store: SignInStore
        let authStore: AuthStore
        let repository: FakeAuthRepository
        let google: FakeGoogleAuthProvider
        let sleeper: ManualSleeper
    }

    private func makeHarness(name: String? = nil) -> Harness {
        let repository = FakeAuthRepository()
        let google = FakeGoogleAuthProvider()
        let sleeper = ManualSleeper()
        let service = AuthService(repository: repository, googleAuthProvider: google)
        let authStore = AuthStore(service: service, sleep: sleeper.sleep)
        return Harness(
            store: authStore.makeSignInStore(entry: name.map { .onboarding(name: $0) } ?? .signIn),
            authStore: authStore,
            repository: repository,
            google: google,
            sleeper: sleeper
        )
    }

    @Test func continueIsOnlyOfferedForAValidEmail() {
        let store = makeHarness().store

        store.email = "a@b"
        #expect(!store.canSendCode)

        store.email = " a@b.com "
        #expect(store.canSendCode)
    }

    @Test func sendingTheCodeOpensTheCodeScreen() async {
        let harness = makeHarness()
        let sentTo = Locked<String?>(nil)
        harness.repository.sendSignInCodeHandler = { email in sentTo.value = email }
        harness.store.email = " a@b.com "

        await harness.store.sendCode()

        #expect(sentTo.value == "a@b.com")
        #expect(harness.store.step == .code(email: "a@b.com"))
    }

    @Test func whileTheCodeIsBeingSentGoogleIsDisabled() async {
        let harness = makeHarness()
        let (gate, release) = AsyncStream<Void>.makeStream()
        harness.repository.sendSignInCodeHandler = { _ in for await _ in gate { return } }
        harness.store.email = "a@b.com"

        let sending = Task { await harness.store.sendCode() }
        #expect(await eventually { harness.store.isSendingCode })
        #expect(!harness.store.canUseGoogle)
        #expect(!harness.store.canSendCode)

        release.yield()
        await sending.value
        #expect(!harness.store.isSendingCode)
        #expect(harness.store.canUseGoogle)
    }

    @Test func theSixthDigitSignsInWithTheCodeAndTheName() async {
        let harness = makeHarness(name: "Ada Lovelace")
        let user = AuthUser(id: "1", email: "a@b.com", name: "Ada Lovelace")
        let received = Locked<[String?]>([])
        harness.repository.signInHandler = { email, code, name in
            received.value = [email, code, name]
            return user
        }
        await harness.openCodeScreen(email: "a@b.com")

        harness.store.enterCode("12345")
        #expect(harness.store.code == "12345")
        harness.store.enterCode("123 456")

        #expect(await eventually { harness.authStore.state == .signedIn(user) })
        #expect(received.value == ["a@b.com", "123456", "Ada Lovelace"])
    }

    @Test func aWrongCodeClearsTheBoxes() async {
        let harness = makeHarness()
        harness.repository.signInHandler = { (_, _, _) throws(AuthError) in throw .invalidCode }
        await harness.openCodeScreen(email: "a@b.com")

        harness.store.enterCode("111111")

        #expect(await eventually { harness.store.codeProblem == .wrong })
        #expect(harness.store.code.isEmpty)
        #expect(!harness.store.isCodeEntryDisabled)
        #expect(harness.authStore.state == .checkingSession)

        // Typing the next code takes the red away.
        harness.store.enterCode("2")
        #expect(harness.store.codeProblem == nil)
        #expect(harness.store.code == "2")
    }

    /// The server still answers `INVALID_OTP` to the 3rd wrong code; only the next request
    /// would get `TOO_MANY_ATTEMPTS` (#121), so the app counts the failures itself.
    @Test func theThirdWrongCodeDisablesTheBoxesAndPromotesTheResend() async {
        let harness = makeHarness()
        let attempts = Locked(0)
        harness.repository.signInHandler = { (_, _, _) throws(AuthError) in
            attempts.value += 1
            throw .invalidCode
        }
        await harness.openCodeScreen(email: "a@b.com")

        for attempt in 1 ... 3 {
            harness.store.enterCode("11111\(attempt)")
            #expect(await eventually { attempts.value == attempt && !harness.store.isVerifyingCode })
        }

        #expect(harness.store.codeProblem == .noLongerValid)
        #expect(harness.store.isCodeEntryDisabled)
        #expect(harness.store.canResendCode)
        harness.store.enterCode("1")
        #expect(harness.store.code.isEmpty)
    }

    @Test(arguments: [AuthError.codeExpired, .tooManyAttempts])
    func aCodeNoLongerValidDisablesTheBoxesAndPromotesTheResend(error: AuthError) async {
        let harness = makeHarness()
        harness.repository.signInHandler = { (_, _, _) throws(AuthError) in throw error }
        await harness.openCodeScreen(email: "a@b.com")

        harness.store.enterCode("123456")

        #expect(await eventually { harness.store.codeProblem == .noLongerValid })
        #expect(harness.store.isCodeEntryDisabled)
        #expect(harness.store.code.isEmpty)
        // Right away, without waiting for the 30 s.
        #expect(harness.store.canResendCode)
    }

    @Test func aNewCodeCanOnlyBeRequestedAfterThirtySeconds() async {
        let harness = makeHarness()
        await harness.openCodeScreen(email: "a@b.com")

        #expect(harness.store.resendCountdown == 30)
        #expect(!harness.store.canResendCode)
        for remaining in (0 ..< 30).reversed() {
            #expect(await eventually { harness.sleeper.waiting == 1 })
            harness.sleeper.wakeAll()
            #expect(await eventually { harness.store.resendCountdown == remaining })
        }

        #expect(harness.store.canResendCode)
        #expect(harness.sleeper.requested == Array(repeating: .seconds(1), count: 30))
    }

    @Test func aNewCodeStartsOverWithFreshAttempts() async {
        let harness = makeHarness()
        let sends = Locked(0)
        harness.repository.signInHandler = { (_, _, _) throws(AuthError) in throw .tooManyAttempts }
        await harness.openCodeScreen(email: "a@b.com")
        harness.repository.sendSignInCodeHandler = { email in
            #expect(email == "a@b.com")
            sends.value += 1
        }
        harness.store.enterCode("123456")
        #expect(await eventually { harness.store.codeProblem == .noLongerValid })

        await harness.store.resendCode()

        #expect(sends.value == 1)
        #expect(harness.store.codeProblem == nil)
        #expect(!harness.store.isCodeEntryDisabled)
        #expect(harness.store.resendCountdown == 30)
        #expect(!harness.store.canResendCode)

        harness.repository.signInHandler = { (_, _, _) throws(AuthError) in throw .invalidCode }
        harness.store.enterCode("111111")
        #expect(await eventually { harness.store.codeProblem == .wrong })
    }

    @Test(arguments: [
        (AuthError.rateLimited, SignInStore.FormError.rateLimited),
        (AuthError.network(.offline), SignInStore.FormError.offline),
    ])
    func aCodeThatCannotBeSentStaysOnTheEmail(error: AuthError, expected: SignInStore.FormError) async {
        let harness = makeHarness()
        harness.repository.sendSignInCodeHandler = { (_: String) throws(AuthError) in throw error }
        harness.store.email = "a@b.com"

        await harness.store.sendCode()

        #expect(harness.store.step == .email)
        #expect(harness.store.formError == expected)
        #expect(harness.store.canSendCode)
    }

    /// Neither is a wrong code: the boxes are cleared for another try, with no red.
    @Test(arguments: [
        (AuthError.rateLimited, SignInStore.FormError.rateLimited),
        (AuthError.network(.offline), SignInStore.FormError.offline),
    ])
    func aCodeThatCannotBeCheckedCanBeTypedAgain(error: AuthError, expected: SignInStore.FormError) async {
        let harness = makeHarness()
        harness.repository.signInHandler = { (_, _, _) throws(AuthError) in throw error }
        await harness.openCodeScreen(email: "a@b.com")

        harness.store.enterCode("123456")

        #expect(await eventually { harness.store.formError == expected })
        #expect(harness.store.code.isEmpty)
        #expect(harness.store.codeProblem == nil)
        #expect(!harness.store.isCodeEntryDisabled)

        harness.store.enterCode("1")
        #expect(harness.store.formError == nil)
    }

    @Test func aResendThatCannotBeSentSaysWhy() async {
        let harness = makeHarness()
        harness.repository.signInHandler = { (_, _, _) throws(AuthError) in throw .codeExpired }
        await harness.openCodeScreen(email: "a@b.com")
        harness.store.enterCode("123456")
        #expect(await eventually { harness.store.codeProblem == .noLongerValid })
        harness.repository.sendSignInCodeHandler = { (_: String) throws(AuthError) in throw .rateLimited }

        await harness.store.resendCode()

        #expect(harness.store.formError == .rateLimited)
        #expect(harness.store.codeProblem == .noLongerValid)
        #expect(harness.store.canResendCode)
    }

    @Test func continuingWithGoogleSignsIn() async {
        let harness = makeHarness()
        let user = AuthUser(id: "2", email: "g@b.com", name: "Gina")
        harness.google.signInHandler = { "id-token" }
        harness.repository.signInWithGoogleHandler = { _ in user }

        await harness.store.signInWithGoogle()

        #expect(harness.authStore.state == .signedIn(user))
    }

    @Test func cancellingGoogleIsNotAnError() async {
        let harness = makeHarness()
        harness.google.signInHandler = { () throws(AuthError) in throw .googleSignInCancelled }

        await harness.store.signInWithGoogle()

        #expect(harness.store.formError == nil)
        #expect(harness.authStore.state == .checkingSession)
    }

    @Test func aGoogleFailureSaysWhy() async {
        let harness = makeHarness()
        harness.google.signInHandler = { () throws(AuthError) in throw .googleSignInFailed("no ID token") }

        await harness.store.signInWithGoogle()

        #expect(harness.store.formError == .message("Google : no ID token"))
    }

    @Test func goingBackToTheEmailLetsTheAddressBeChanged() async {
        let harness = makeHarness()
        await harness.openCodeScreen(email: "a@b.com")

        harness.store.editEmail()

        #expect(harness.store.step == .email)
        #expect(harness.store.email == "a@b.com")
        await harness.openCodeScreen(email: "c@d.com")
        #expect(harness.store.resendCountdown == 30)
    }
}

@MainActor
extension SignInStoreTests.Harness {
    /// The account screen sent a code to `email`: the code screen is open.
    func openCodeScreen(email: String) async {
        repository.sendSignInCodeHandler = { _ in }
        store.email = email
        await store.sendCode()
        #expect(store.step == .code(email: email))
    }
}
