import XCTest

/// Home / camera / history navigation. Does not run OCR, so it does not depend on the test images.
final class NavigationFlowTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "YES", "-ocrSuccessCount", "999",
                                "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
    }

    func testHomeToCameraAndBack() throws {
        let camera = app.buttons["home_camera_button"]
        XCTAssertTrue(camera.waitForExistence(timeout: 120), "home screen should appear")
        camera.tap()

        let home = app.buttons["home_button"]
        XCTAssertTrue(home.waitForExistence(timeout: 10), "camera screen should show the home button")
        home.tap()

        XCTAssertTrue(app.buttons["home_camera_button"].waitForExistence(timeout: 10), "should return to home")
    }

    func testHistoryOpensFromHome() throws {
        let history = app.buttons["home_history_button"]
        XCTAssertTrue(history.waitForExistence(timeout: 120))
        history.tap()
        // Empty or not, the history sheet shows its title / list.
        let title = app.navigationBars.firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["履歴"].exists)
    }
}
