import XCTest

/// COPPA surfaces: the neutral age question on sign-up, the remembered
/// under-13 block, the auth-screen privacy link, and the one-time upload
/// confirmation before the first swing photo/video.
final class AgeGateUITests: BarrelUITestCase {
    private var thisYear: Int { Calendar.current.component(.year, from: Date()) }

    private func launchSignedOut(keepAgeGate: Bool = false) {
        app.launchArguments = ["-uiTestSignedOut"] + (keepAgeGate ? ["-uiTestKeepAgeGate"] : [])
        app.launch()
    }

    private func openEmailSignUp() {
        waitForHittable(app.buttons["Continue with email"], timeout: 10).tap()
        waitForHittable(app.buttons["emailAuthModeToggle"]).tap()
    }

    private func answerAge(month: String, year: Int) {
        let wheels = app.pickerWheels
        XCTAssertTrue(wheels.element(boundBy: 1).waitForExistence(timeout: 6))
        wheels.element(boundBy: 0).adjust(toPickerWheelValue: month)
        wheels.element(boundBy: 1).adjust(toPickerWheelValue: String(year))
        let cont = app.buttons["ageGateContinueButton"]
        XCTAssertTrue(cont.isEnabled)
        cont.tap()
    }

    func testAuthScreenLinksThePrivacyPolicy() {
        launchSignedOut()
        XCTAssertTrue(app.links["authPrivacyLink"].waitForExistence(timeout: 10)
                      || app.buttons["authPrivacyLink"].exists)
    }

    func testSignUpAsksAgeWithNothingPreselected() {
        launchSignedOut()
        openEmailSignUp()
        let cont = waitFor(app.buttons["ageGateContinueButton"])
        XCTAssertFalse(cont.isEnabled, "Continue must wait for an answer")
        XCTAssertEqual(app.pickerWheels.element(boundBy: 0).value as? String, "Month")
        XCTAssertEqual(app.pickerWheels.element(boundBy: 1).value as? String, "Year")
        XCTAssertFalse(app.textFields["Email"].exists, "Sign-up fields come after the age question")
    }

    func testThirteenPlusContinuesToSignUpForm() {
        launchSignedOut()
        openEmailSignUp()
        answerAge(month: "June", year: thisYear - 30)
        XCTAssertTrue(app.textFields["Display name"].waitForExistence(timeout: 6))
        XCTAssertEqual(app.buttons["emailAuthSubmitButton"].label, "Create Account")
    }

    func testUnderThirteenIsBlockedAndRemembered() {
        launchSignedOut()
        openEmailSignUp()
        answerAge(month: "March", year: thisYear - 8)

        XCTAssertTrue(app.staticTexts["ageBlockedTitle"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Continue with email"].exists)

        // Relaunch without wiping the gate: still blocked, no way back to sign-up.
        app.terminate()
        launchSignedOut(keepAgeGate: true)
        XCTAssertTrue(app.staticTexts["ageBlockedTitle"].waitForExistence(timeout: 10))

        // A parent or coach can still sign in, but the sheet has no sign-up.
        waitForHittable(app.buttons["ageBlockedSignInButton"]).tap()
        XCTAssertTrue(app.buttons["emailAuthSubmitButton"].waitForExistence(timeout: 6))
        XCTAssertEqual(app.buttons["emailAuthSubmitButton"].label, "Sign In")
        XCTAssertFalse(app.buttons["emailAuthModeToggle"].exists)
    }

    func testFirstSwingUploadNeedsOneTimeConfirmation() {
        launch(extraArguments: ["-uiTestAITab"])
        waitForHittable(app.tabBars.buttons["AI"], timeout: 10).tap()

        let attach = waitForHittable(app.buttons["attachSwingButton"])
        attach.tap()
        XCTAssertTrue(app.staticTexts["uploadAttestationTitle"].waitForExistence(timeout: 6))

        // "Not now" stores nothing: the next tap asks again.
        app.buttons["uploadAttestationCancel"].tap()
        XCTAssertTrue(app.staticTexts["uploadAttestationTitle"].waitForNonExistence(timeout: 6))
        waitForHittable(attach).tap()
        XCTAssertTrue(app.staticTexts["uploadAttestationTitle"].waitForExistence(timeout: 6))

        app.buttons["uploadAttestationConfirm"].tap()
        XCTAssertTrue(app.staticTexts["uploadAttestationTitle"].waitForNonExistence(timeout: 6))
    }
}
