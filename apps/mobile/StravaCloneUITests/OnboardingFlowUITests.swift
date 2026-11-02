import XCTest

/// The Onboarding (ADR-035 §1, §5), from the Welcome to the account screen, and its resumption
/// after the app is killed. No backend needed: it stops on the account screen.
@MainActor
final class OnboardingFlowUITests: XCTestCase {
    private func launch(fresh: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestDisableSplash"]
        if fresh {
            app.launchArguments += ["-uiTestResetAuth", "-uiTestResetMeasurementConsent", "-uiTestResetOnboarding"]
        }
        app.launch()
        if fresh {
            let refuse = app.buttons["consent.refuse"]
            XCTAssertTrue(refuse.waitForExistence(timeout: 5))
            refuse.tap()
            XCTAssertTrue(refuse.waitForNonExistence(timeout: 5))
        }
        return app
    }

    private func createAccount(in app: XCUIApplication) {
        let button = app.buttons["welcome.createAccount"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
    }

    private func continueButton(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["onboarding.continue"]
    }

    private func tapContinue(in app: XCUIApplication) {
        let button = continueButton(app)
        XCTAssertTrue(button.isEnabled)
        button.tap()
    }

    /// Name, birth date (the wheel's 30 years ago) and gender.
    private func answerFirstThreeQuestions(in app: XCUIApplication) {
        let firstName = app.textFields["onboarding.firstName"]
        XCTAssertTrue(firstName.waitForExistence(timeout: 5))
        firstName.tap()
        firstName.typeText("Camille")
        XCTAssertFalse(continueButton(app).isEnabled)
        let lastName = app.textFields["onboarding.lastName"]
        lastName.tap()
        lastName.typeText("Martin")
        tapContinue(in: app)

        XCTAssertTrue(app.staticTexts["Bienvenue, Camille ! Quelle est votre date de naissance ?"].waitForExistence(timeout: 5))
        XCTAssertFalse(continueButton(app).isEnabled)
        app.buttons["onboarding.birthDate"].tap()
        tapContinue(in: app)

        XCTAssertTrue(app.staticTexts["Quel est votre genre ?"].waitForExistence(timeout: 5))
        app.buttons["onboarding.gender.female"].tap()
        tapContinue(in: app)
    }

    func testTheOnboardingLeadsToTheAccountScreen() {
        let app = launch(fresh: true)
        createAccount(in: app)
        answerFirstThreeQuestions(in: app)

        XCTAssertTrue(app.staticTexts["Quels sports pratiquez-vous ?"].waitForExistence(timeout: 5))
        XCTAssertFalse(continueButton(app).isEnabled)
        app.buttons["onboarding.sport.run"].tap()
        app.buttons["onboarding.sport.ride"].tap()
        tapContinue(in: app)

        XCTAssertTrue(app.staticTexts["Qu'attendez-vous de Nervo ?"].waitForExistence(timeout: 5))
        XCTAssertEqual(continueButton(app).label, "Passer")
        tapContinue(in: app)

        XCTAssertTrue(app.staticTexts["Où en êtes-vous dans votre pratique ?"].waitForExistence(timeout: 5))
        XCTAssertFalse(continueButton(app).isEnabled)
        app.buttons["onboarding.level.intermediate"].tap()
        tapContinue(in: app)

        let skip = app.buttons["onboarding.showcase.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()

        let createMyAccount = app.buttons["onboarding.createAccount"]
        XCTAssertTrue(createMyAccount.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Tout est prêt, Camille !"].exists)
        createMyAccount.tap()

        XCTAssertTrue(app.textFields["account.email"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Créer un compte"].exists)
    }

    /// Decision on #128: the first screen's back button leads to the Welcome, the draft kept.
    func testTheFirstScreenGoesBackToTheWelcomeKeepingTheNames() {
        let app = launch(fresh: true)
        createAccount(in: app)
        let firstName = app.textFields["onboarding.firstName"]
        XCTAssertTrue(firstName.waitForExistence(timeout: 5))
        firstName.tap()
        firstName.typeText("Camille")

        app.buttons["onboarding.back"].tap()
        createAccount(in: app)

        XCTAssertTrue(firstName.waitForExistence(timeout: 5))
        XCTAssertEqual(firstName.value as? String, "Camille")
    }

    func testAKilledOnboardingResumesWhereItStopped() {
        var app = launch(fresh: true)
        createAccount(in: app)
        answerFirstThreeQuestions(in: app)
        XCTAssertTrue(app.staticTexts["Quels sports pratiquez-vous ?"].waitForExistence(timeout: 5))

        app.terminate()
        app = launch(fresh: false)
        createAccount(in: app)

        XCTAssertTrue(app.staticTexts["Quels sports pratiquez-vous ?"].waitForExistence(timeout: 5))
        app.buttons["onboarding.back"].tap()
        XCTAssertTrue(app.staticTexts["Quel est votre genre ?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboarding.gender.female"].isSelected)
        XCTAssertTrue(continueButton(app).isEnabled)
    }
}
