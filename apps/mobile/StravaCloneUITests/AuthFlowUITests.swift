import XCTest

/// Critical flow (ADR-025 §2): sign-up then sign-in with email/password, against a
/// real local backend (`docker-compose.dev.yml` + `pnpm dev` for `apps/api` must be
/// running — no HTTP mock here, this exercises the app end-to-end). Google sign-in is
/// not driven here (third-party SDK UI, out of our control) — only its button presence
/// is checked.
@MainActor
final class AuthFlowUITests: XCTestCase {
    private func launchSignedOutApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestResetAuth"]
        app.launch()
        return app
    }

    private func uniqueEmail() -> String {
        "uitest+\(Int(Date().timeIntervalSince1970))@example.com"
    }

    func testSignUpThenSignInReachesTheTabView() {
        let app = launchSignedOutApp()
        let email = uniqueEmail()
        let password = "correct horse battery staple"

        // 1. Sign up.
        XCTAssertTrue(app.staticTexts["Continuer avec Google"].waitForExistence(timeout: 5))
        app.buttons["Pas de compte ? Créer un compte"].tap()

        let nameField = app.textFields["signUp.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("UI Test")

        let emailField = app.textFields["signUp.email"]
        emailField.tap()
        emailField.typeText(email)

        let passwordField = app.secureTextFields["signUp.password"]
        passwordField.tap()
        passwordField.typeText(password)

        app.buttons["signUp.submit"].tap()

        // 2. Reaching the TabView confirms signedIn.
        let feedTab = app.tabBars.buttons["Fil"]
        XCTAssertTrue(feedTab.waitForExistence(timeout: 10))

        // 3. Sign out from the "Compte" tab.
        app.tabBars.buttons["Compte"].tap()
        app.buttons["Se déconnecter"].tap()

        // 4. Sign in again with the same credentials.
        let signInEmailField = app.textFields["signIn.email"]
        XCTAssertTrue(signInEmailField.waitForExistence(timeout: 5))
        signInEmailField.tap()
        signInEmailField.typeText(email)

        let signInPasswordField = app.secureTextFields["signIn.password"]
        signInPasswordField.tap()
        signInPasswordField.typeText(password)

        app.buttons["signIn.submit"].tap()

        XCTAssertTrue(feedTab.waitForExistence(timeout: 10))
    }
}
