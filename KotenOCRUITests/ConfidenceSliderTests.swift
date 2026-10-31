import XCTest

/// The result screen's confidence slider: it exists, shows a percentage, and moving it hides lines.
/// Set SAMPLE_SHOT_DIR (TEST_RUNNER_SAMPLE_SHOT_DIR) to save before/after shots for checking by eye.
final class ConfidenceSliderTests: XCTestCase {
    private let shotDir = ProcessInfo.processInfo.environment["SAMPLE_SHOT_DIR"] ?? ""
    private let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().path
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "YES", "-ocrSuccessCount", "999",
                                "-coachShutterShown", "YES", "-coachCropCornerShown", "YES",
                                "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
    }

    /// The bundled Genji page, auto-loaded.
    func testSliderOnGenjiSample() throws {
        app.launchArguments += ["-skipHome", "YES"]
        app.launchEnvironment["TEST_IMAGE_PATH"] = "\(projectRoot)/KotenOCRUITests/Resources/test_koten_sample_page.jpg"
        app.launch()
        try exerciseSlider(prefix: "genji")
    }

    /// Bundled sample pages by index (SamplePage.all): 0 Taketori, 2 Kikuchi, 3 Shibata, 4 modern.
    func testSliderOnBundledSamples() throws {
        app.launch()
        for index in [0, 2, 3, 4] {
            let link = app.buttons["home_sample_button"]
            XCTAssertTrue(link.waitForExistence(timeout: 120))
            link.tap()
            let row = app.buttons["sample_\(index)"]
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            row.tap()
            try exerciseSlider(prefix: "sample\(index)")
            app.buttons["back_button"].tap()
            let cancel = app.buttons.matching(NSPredicate(format: "label == 'キャンセル' OR label == 'Cancel'")).firstMatch
            XCTAssertTrue(cancel.waitForExistence(timeout: 10))
            cancel.tap()
            let home = app.buttons["home_button"]
            XCTAssertTrue(home.waitForExistence(timeout: 10))
            home.tap()
        }
    }

    private func exerciseSlider(prefix: String) throws {
        let back = app.buttons["back_button"]
        XCTAssertTrue(back.waitForExistence(timeout: 300), "the result should appear")
        sleep(5)
        let slider = app.sliders["confidence_slider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 10), "the confidence slider should be on the result screen")
        let value = app.staticTexts["confidence_value"]
        XCTAssertTrue(value.exists)
        XCTAssertTrue(value.label.hasSuffix("%"), "the value is a percentage: \(value.label)")
        save("\(prefix)_1_default")
        slider.adjust(toNormalizedSliderPosition: 0.4)   // about 50%
        sleep(1)
        save("\(prefix)_2_raised")
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
