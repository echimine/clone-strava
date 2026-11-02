import XCTest

/// Critical flow (ADR-025 §2, ADR-035 §2): sign-in by Sign-in code, against a real local
/// backend (`docker-compose.dev.yml` + `pnpm dev` for `apps/api` must be running, so with
/// `NODE_ENV=development` — no HTTP mock here, this exercises the app end-to-end). In
/// development, `@stravaclone.test` addresses get the fixed code `000000` without any email.
/// Google sign-in is not driven here (third-party SDK UI, out of our control) — only its
/// button presence is checked.
///
/// The notification priming screen (ADR-035 §7) only shows while iOS has not asked yet: to see
/// it and iOS's prompt, uninstall the app from the simulator before the run
/// (`xcrun simctl uninstall <device> fr.echimine.StravaClone`). Otherwise it is skipped, as for a
/// second account on the same phone.
@MainActor
final class AuthFlowUITests: XCTestCase {
    private func launchSignedOutApp() -> XCUIApplication {
        let app = XCUIApplication()
        // The animated splash (ADR-032 §4) is skipped: it only delays the first screen.
        app.launchArguments += [
            "-uiTestResetAuth", "-uiTestDisableSplash", "-uiTestResetMeasurementConsent", "-uiTestResetOnboarding",
        ]
        app.launch()
        return app
    }

    /// First launch (ADR-035 §8): the Measurement consent sheet opens over the Welcome.
    private func refuseMeasurement(in app: XCUIApplication) {
        let refuse = app.buttons["consent.refuse"]
        XCTAssertTrue(refuse.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["consent.accept"].exists)
        refuse.tap()
        XCTAssertTrue(refuse.waitForNonExistence(timeout: 5))
    }

    /// "Se connecter" on the Welcome opens the account screen.
    private func openSignIn(in app: XCUIApplication) {
        let signIn = app.buttons["welcome.signIn"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["welcome.createAccount"].exists)
        signIn.tap()
    }

    /// A new address each run, so the first code also creates the account.
    private func uniqueEmail() -> String {
        "uitest+\(Int(Date().timeIntervalSince1970))@stravaclone.test"
    }

    private func signInWithCode(email: String, in app: XCUIApplication) {
        let emailField = app.textFields["account.email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["account.google"].exists)
        XCTAssertFalse(app.buttons["account.continue"].isEnabled)
        emailField.tap()
        emailField.typeText(email)
        app.buttons["account.continue"].tap()

        XCTAssertTrue(app.staticTexts["Nous vous avons envoyé un code"].waitForExistence(timeout: 10))
        let codeField = app.textFields["signInCode.field"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["signInCode.resend"].isEnabled)
        codeField.tap()
        // The 6th digit submits the code: there is no button to tap.
        codeField.typeText("000000")
    }

    /// The six questions, "Voici ce qui vous attend" skipped, up to "Créer mon compte".
    private func answerTheOnboarding(in app: XCUIApplication) {
        let firstName = app.textFields["onboarding.firstName"]
        XCTAssertTrue(firstName.waitForExistence(timeout: 10))
        firstName.tap()
        firstName.typeText("Camille")
        let lastName = app.textFields["onboarding.lastName"]
        lastName.tap()
        lastName.typeText("Martin")
        let next = app.buttons["onboarding.continue"]
        next.tap()
        app.buttons["onboarding.birthDate"].tap()
        next.tap()
        XCTAssertTrue(app.buttons["onboarding.gender.female"].waitForExistence(timeout: 5))
        app.buttons["onboarding.gender.female"].tap()
        next.tap()
        XCTAssertTrue(app.buttons["onboarding.sport.ride"].waitForExistence(timeout: 5))
        app.buttons["onboarding.sport.ride"].tap()
        app.buttons["onboarding.sport.run"].tap()
        next.tap()
        XCTAssertTrue(app.buttons["onboarding.goal.health"].waitForExistence(timeout: 5))
        app.buttons["onboarding.goal.health"].tap()
        next.tap()
        XCTAssertTrue(app.buttons["onboarding.level.intermediate"].waitForExistence(timeout: 5))
        app.buttons["onboarding.level.intermediate"].tap()
        next.tap()
        let skip = app.buttons["onboarding.showcase.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()
        let createMyAccount = app.buttons["onboarding.createAccount"]
        XCTAssertTrue(createMyAccount.waitForExistence(timeout: 10))
        createMyAccount.tap()
    }

    /// The Paywall (ADR-035 §6), left by "Essayer" or "Non merci": nothing is bought.
    private func leaveThePaywall(in app: XCUIApplication, byStartingTheTrial: Bool) {
        let button = app.buttons[byStartingTheTrial ? "paywall.startTrial" : "paywall.skip"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
    }

    /// The priming screen, then iOS's prompt once (ADR-035 §7). Returns false when iOS had
    /// already asked: the step is skipped silently.
    @discardableResult
    private func enableNotificationsIfAsked(in app: XCUIApplication) -> Bool {
        let enable = app.buttons["notificationPrimer.enable"]
        let feedTab = app.tabBars.buttons["Accueil"]
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        guard enable.waitForExistence(timeout: 5) else {
            XCTAssertTrue(feedTab.waitForExistence(timeout: 5))
            return false
        }
        XCTAssertTrue(app.staticTexts["Ne manquez rien"].exists)
        XCTAssertTrue(app.buttons["notificationPrimer.later"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "notification-primer"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        // iOS's prompt opens only after the priming screen.
        XCTAssertFalse(springboard.alerts.firstMatch.exists)
        enable.tap()

        let prompt = springboard.alerts.firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        let allow = prompt.buttons.matching(NSPredicate(format: "label IN %@", ["Autoriser", "Allow"])).firstMatch
        XCTAssertTrue(allow.exists)
        allow.tap()
        XCTAssertTrue(prompt.waitForNonExistence(timeout: 5))
        XCTAssertTrue(feedTab.waitForExistence(timeout: 10))
        XCTAssertFalse(springboard.alerts.firstMatch.exists)
        return true
    }

    /// ADR-035 §1, §5: the Onboarding, its account screen, then the home screen at once; the
    /// answers are sent in the background (check `users.user_profile` of the new account). Then
    /// the Paywall, the notification priming screen and iOS's prompt (§6, §7), then home.
    func testCreatingAnAccountAtTheEndOfTheOnboardingReachesTheTabView() {
        let app = launchSignedOutApp()
        refuseMeasurement(in: app)
        let createAccount = app.buttons["welcome.createAccount"]
        XCTAssertTrue(createAccount.waitForExistence(timeout: 5))
        createAccount.tap()
        answerTheOnboarding(in: app)

        signInWithCode(email: uniqueEmail(), in: app)
        leaveThePaywall(in: app, byStartingTheTrial: true)
        enableNotificationsIfAsked(in: app)

        XCTAssertTrue(app.tabBars.buttons["Accueil"].waitForExistence(timeout: 10))
    }

    func testSignInByCodeOnANewAccountGoesThroughTheOnboardingAndAnExistingOneGoesHome() {
        let app = launchSignedOutApp()
        let feedTab = app.tabBars.buttons["Accueil"]

        // 1. The first code creates the account: "Se connecter" goes through the Onboarding
        //    (ADR-035 §1), whose "Créer mon compte" goes to the Paywall without the account
        //    screen, then the notification step (§7), then home.
        refuseMeasurement(in: app)
        openSignIn(in: app)
        signInWithCode(email: uniqueEmail(), in: app)
        answerTheOnboarding(in: app)
        leaveThePaywall(in: app, byStartingTheTrial: false)
        enableNotificationsIfAsked(in: app)
        XCTAssertTrue(feedTab.waitForExistence(timeout: 10))

        // 2. Sign out from the "Profil" tab.
        app.tabBars.buttons["Profil"].tap()
        app.buttons["Se déconnecter"].tap()

        // 3. An existing account goes home; the consent is not asked again.
        openSignIn(in: app)
        XCTAssertFalse(app.buttons["consent.refuse"].exists)
        signInWithCode(email: "test.map@stravaclone.test", in: app)
        XCTAssertTrue(feedTab.waitForExistence(timeout: 10))
        XCTAssertFalse(app.textFields["onboarding.firstName"].exists)
        XCTAssertFalse(app.buttons["notificationPrimer.enable"].exists)
    }
}
