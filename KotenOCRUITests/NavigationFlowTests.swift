import XCTest

/// Home / camera / history navigation. Does not run OCR, so it does not depend on the test images.
final class NavigationFlowTests: XCTestCase {

    private var app: XCUIApplication!

    /// One-time coach marks are marked as already shown, so they do not cover the buttons.
    private let coachMarksShown = ["-coachShutterShown", "YES", "-coachCropCornerShown", "YES"]

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "YES", "-ocrSuccessCount", "999",
                                "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
    }

    func testHomeToCameraAndBack() throws {
        app.launchArguments += coachMarksShown
        app.launch()
        let camera = app.buttons["home_camera_button"]
        XCTAssertTrue(camera.waitForExistence(timeout: 120), "home screen should appear")
        camera.tap()

        let home = app.buttons["home_button"]
        XCTAssertTrue(home.waitForExistence(timeout: 10), "camera screen should show the home button")
        home.tap()

        XCTAssertTrue(app.buttons["home_camera_button"].waitForExistence(timeout: 10), "should return to home")
    }

    func testHistoryOpensFromHome() throws {
        app.launchArguments += coachMarksShown
        app.launch()
        let history = app.buttons["home_history_button"]
        XCTAssertTrue(history.waitForExistence(timeout: 120))
        history.tap()
        // Empty or not, the history sheet shows its title / list.
        let title = app.navigationBars.firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["履歴"].exists)
    }

    /// The shutter hint shows once, is dismissed by a tap, and does not come back.
    func testShutterCoachMarkShowsOnce() throws {
        app.launchArguments += ["-coachShutterShown", "NO"]
        app.launch()
        let camera = app.buttons["home_camera_button"]
        XCTAssertTrue(camera.waitForExistence(timeout: 120))
        camera.tap()

        let coach = app.descendants(matching: .any)["coach_shutter"]
        XCTAssertTrue(coach.waitForExistence(timeout: 5), "hint should appear on first camera visit")
        coach.tap()
        XCTAssertTrue(coach.waitForNonExistence(timeout: 3), "hint should go away after a tap")

        app.buttons["home_button"].tap()
        XCTAssertTrue(camera.waitForExistence(timeout: 10))
        camera.tap()
        XCTAssertTrue(app.buttons["home_button"].waitForExistence(timeout: 10))
        XCTAssertFalse(coach.waitForExistence(timeout: 2), "hint should not show a second time")
    }
}
