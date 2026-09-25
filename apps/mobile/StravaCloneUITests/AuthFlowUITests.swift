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

    /// `SecureField.typeText(_:)` in one call has been observed to only commit the
    /// last character to the SwiftUI binding on this simulator/Xcode combo (confirmed
    /// by capturing the actual sign-up request body: a 28-character password arrived
    /// as a single digit server-side). Typing one character per `typeText` call, with
    /// a short pause to let the binding catch up, is the known workaround.
    ///
    /// Typing immediately after `tap()` can still race the field taking keyboard
    /// focus, silently dropping the first character(s) (observed server-side as
    /// "Password is too short"). Wait for the field to report focus, then verify the
    /// committed value afterwards and retry the whole entry once if it doesn't match —
    /// cheaper than trying to prove there's no remaining race.
    ///
    /// iOS's "Use Strong Password?" system sheet can also pop up mid-typing (it isn't
    /// only triggered by `.textContentType(.newPassword)` — the keyboard heuristically
    /// offers it for any password-looking field) and steals the remaining keystrokes.
    /// Dismiss it between attempts if it showed up.
    private func type(_ text: String, into field: XCUIElement, in app: XCUIApplication) {
        for attempt in 1...2 {
            waitForFocus(of: field)
            for character in text {
                field.typeText(String(character))
                usleep(80_000) // 80ms
            }
            dismissStrongPasswordSuggestionIfPresent(in: app)
            if valueMatches(text, in: field) { return }
            if attempt == 1 {
                clear(field, in: app)
            }
        }
        XCTFail("Failed to type expected value into \(field) after retry")
    }

    /// The system's "Utiliser un mot de passe robuste ?" card (confirmed via
    /// `debugDescription` dump) has no "use my own password" button — only its "✕"
    /// close button (accessibility identifier "xmark", label "Fermer") and the
    /// "Utiliser un mot de passe robuste" action, which would overwrite our field with
    /// iOS's own generated password. Closing it is the only safe dismissal.
    private func dismissStrongPasswordSuggestionIfPresent(in app: XCUIApplication) {
        let closeButton = app.buttons["xmark"]
        if closeButton.waitForExistence(timeout: 1) {
            closeButton.tap()
        }
    }

    private func waitForFocus(of field: XCUIElement, timeout: TimeInterval = 3) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (field.value(forKey: "hasKeyboardFocus") as? Bool) == true { return }
            usleep(50_000)
        }
    }

    /// Secure fields report their value as a bullet mask, not the typed text, so this
    /// only checks the committed length — enough to catch the dropped-character race.
    private func valueMatches(_ text: String, in field: XCUIElement) -> Bool {
        guard let value = field.value as? String else { return false }
        if field.elementType == .secureTextField {
            return value.count == text.count
        }
        return value == text
    }

    private func clear(_ field: XCUIElement, in app: XCUIApplication) {
        field.tap()
        guard let value = field.value as? String, !value.isEmpty else { return }
        let deleteAll = String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count)
        field.typeText(deleteAll)
    }

    func testSignUpThenSignInReachesTheTabView() {
        let app = launchSignedOutApp()
        let email = uniqueEmail()
        // No spaces: XCUITest's typeText on a hardware-keyboard-connected simulator can
        // drop or mis-send a space (observed as "Password is too short" server-side —
        // the field actually received fewer characters than intended).
        let password = "CorrectHorseBatteryStaple123"

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
        type(password, into: passwordField, in: app)

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
        type(password, into: signInPasswordField, in: app)

        app.buttons["signIn.submit"].tap()

        XCTAssertTrue(feedTab.waitForExistence(timeout: 10))
    }
}
