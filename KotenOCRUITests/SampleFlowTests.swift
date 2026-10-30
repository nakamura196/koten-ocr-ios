import XCTest

/// Home → "Try a sample page" → each bundled page reads through to the result screen,
/// one after another in the same session (the second scan is where 1.3.5 crashed).
final class SampleFlowTests: XCTestCase {

    /// Optional (TEST_RUNNER_SAMPLE_SHOT_DIR): save each screen, for checking by eye.
    private let shotDir = ProcessInfo.processInfo.environment["SAMPLE_SHOT_DIR"] ?? ""
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "YES", "-ocrSuccessCount", "999",
                                "-coachShutterShown", "YES", "-coachCropCornerShown", "YES",
                                "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
    }

    func testEachSampleReadsToResult() throws {
        app.launch()
        for index in 0..<5 {   // SamplePage.all
            let link = app.buttons["home_sample_button"]
            XCTAssertTrue(link.waitForExistence(timeout: 120), "home should show the sample link")
            link.tap()

            let row = app.buttons["sample_\(index)"]
            XCTAssertTrue(row.waitForExistence(timeout: 10), "sample sheet should list page \(index)")
            if index == 0 { sleep(1); save("sample_sheet") }
            row.tap()

            let back = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier == 'back_button'")).firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 300), "sample \(index) should reach the result")
            sleep(4)
            save("sample_\(index)")

            // Result → confirm → camera → home, as a reader would.
            back.tap()
            let cancel = app.buttons.matching(
                NSPredicate(format: "label == 'キャンセル' OR label == 'Cancel'")
            ).firstMatch
            XCTAssertTrue(cancel.waitForExistence(timeout: 10))
            cancel.tap()
            let home = app.buttons["home_button"]
            XCTAssertTrue(home.waitForExistence(timeout: 10))
            home.tap()
        }
        XCTAssertTrue(app.buttons["home_sample_button"].waitForExistence(timeout: 10))
        save("sample_home_after")
    }

    private func save(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard !shotDir.isEmpty else { return }
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: shotDir).appendingPathComponent("\(name).png"))
    }
}
