import XCTest

/// Critical flow (ADR-025 §2, ADR-035 §2): sign-in by Sign-in code, against a real local
/// backend (`docker-compose.dev.yml` + `pnpm dev` for `apps/api` must be running, so with
/// `NODE_ENV=development` — no HTTP mock here, this exercises the app end-to-end). In
/// development, `@stravaclone.test` addresses get the fixed code `000000` without any email.
/// Google sign-in is not driven here (third-party SDK UI, out of our control) — only its
/// button presence is checked.
@MainActor
final class AuthFlowUITests: XCTestCase {
    private func launchSignedOutApp() -> XCUIApplication {
        let app = XCUIApplication()
        // The animated splash (ADR-032 §4) is skipped: it only delays the first screen.
        app.launchArguments += ["-uiTestResetAuth", "-uiTestDisableSplash"]
        app.launch()
        return app
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

    func testSignInByCodeReachesTheTabViewThenSignsInAgain() {
        let app = launchSignedOutApp()
        let email = uniqueEmail()
        let feedTab = app.tabBars.buttons["Accueil"]

        // 1. The first code creates the account.
        signInWithCode(email: email, in: app)
        XCTAssertTrue(feedTab.waitForExistence(timeout: 10))

        // 2. Sign out from the "Profil" tab.
        app.tabBars.buttons["Profil"].tap()
        app.buttons["Se déconnecter"].tap()

        // 3. The same address signs into the same account.
        signInWithCode(email: email, in: app)
        XCTAssertTrue(feedTab.waitForExistence(timeout: 10))
    }
}
