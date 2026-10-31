import XCTest

/// Captures the main screens in light and dark for design review.
/// Skipped unless DESIGN_SCREENSHOT_DIR is set, e.g.
///   TEST_RUNNER_DESIGN_SCREENSHOT_DIR=/tmp/shots xcodebuild test ... -only-testing:KotenOCRUITests/DesignScreenshotTests
/// Set DESIGN_SOLID_PLATES=YES to capture the iOS 16–25 solid plates instead of Liquid Glass.
final class DesignScreenshotTests: XCTestCase {

    private let outDir = ProcessInfo.processInfo.environment["DESIGN_SCREENSHOT_DIR"] ?? ""
    private let solidPlates = ProcessInfo.processInfo.environment["DESIGN_SOLID_PLATES"] == "YES"
    private let projectRoot = "/Users/nakamura/git/hi/miyako/koten-ocr-ios"

    private var sampleImage: String { "\(projectRoot)/KotenOCRUITests/Resources/test_koten_sample.jpg" }

    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipIf(outDir.isEmpty, "DESIGN_SCREENSHOT_DIR not set")
        try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
    }

    func testLightScreens() throws { try captureAll(theme: "light") }
    func testDarkScreens() throws { try captureAll(theme: "dark") }

    func testOnboarding() throws {
        let app = makeApp(theme: "light", extra: ["-hasCompletedOnboarding", "NO"])
        app.launch()
        usleep(1_000_000)
        shot(app, "onboarding_1_sweep_light")
        usleep(800_000)
        shot(app, "onboarding_2_boxes_light")
        sleep(3)
        shot(app, "onboarding_3_final_light")
    }

    // MARK: - Flow

    private func captureAll(theme: String) throws {
        let suffix = solidPlates ? "\(theme)_solid" : theme

        // 1. Empty history and home without recent scans.
        var app = makeApp(theme: theme)
        app.launch()
        XCTAssertTrue(app.buttons["home_camera_button"].waitForExistence(timeout: 120))
        clearHistory(app)
        app.buttons["home_history_button"].tap()
        sleep(1)
        shot(app, "history_empty_\(suffix)")
        closeSheet(app)
        sleep(1)
        shot(app, "home_empty_\(suffix)")

        // 2. Crop → confirm → scanning → result → translation → copy toast.
        app = makeApp(theme: theme, extra: ["-skipHome", "YES"],
                      env: ["TEST_IMAGE_PATH": sampleImage, "TEST_SHOW_CROP": "YES",
                            "TEST_TRANSLATION_TEXT": "いつの御代のことであったか、女御や更衣が大勢お仕えしていた中に、それほど重い身分ではないが、とりわけ帝のご寵愛を受けている方がいた。"])
        app.launch()
        let crop = app.buttons["crop_button"]
        XCTAssertTrue(crop.waitForExistence(timeout: 120))
        sleep(1)
        shot(app, "crop_\(suffix)")
        crop.tap()
        let run = app.buttons["run_ocr_button"]
        XCTAssertTrue(run.waitForExistence(timeout: 10))
        sleep(1)
        shot(app, "confirm_\(suffix)")
        run.tap()
        usleep(1_200_000)
        shot(app, "scanning_\(suffix)")
        let back = app.buttons["back_button"]
        XCTAssertTrue(back.waitForExistence(timeout: 300))
        usleep(150_000)
        shot(app, "result_stamp_\(suffix)")
        sleep(2)
        shot(app, "result_\(suffix)")
        let tab = app.buttons.matching(NSPredicate(format: "label CONTAINS '現代語訳' OR label CONTAINS 'Translation'")).firstMatch
        if tab.waitForExistence(timeout: 3) {
            tab.tap()
            sleep(1)
            app.buttons["copy_button"].tap()
            usleep(500_000)
            shot(app, "translation_toast_\(suffix)")
        }

        // 3. Camera (simulator placeholder) and settings.
        back.tap()
        let cancel = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Cancel' OR label CONTAINS 'キャンセル'")).firstMatch
        if cancel.waitForExistence(timeout: 5) { cancel.tap() }
        XCTAssertTrue(app.buttons["home_button"].waitForExistence(timeout: 10))
        sleep(1)
        shot(app, "camera_\(suffix)")
        app.buttons["settings_button"].tap()
        sleep(1)
        shot(app, "settings_\(suffix)")

        // 4. Home with recent scans, and history with items.
        app = makeApp(theme: theme)
        app.launch()
        XCTAssertTrue(app.buttons["home_recent_0"].waitForExistence(timeout: 120))
        sleep(1)
        shot(app, "home_\(suffix)")
        app.buttons["home_history_button"].tap()
        sleep(1)
        shot(app, "history_\(suffix)")
    }

    // MARK: - Helpers

    private func makeApp(theme: String, extra: [String] = [], env: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES", "-ocrSuccessCount", "999",
                               "-coachShutterShown", "YES", "-coachCropCornerShown", "YES",
                               "-hasSeenLaunchStamp", "YES", "-appTheme", theme,
                               "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"] + extra
        if solidPlates { app.launchArguments += ["-kotenSolidPlates", "YES"] }
        app.launchEnvironment = env
        return app
    }

    private func clearHistory(_ app: XCUIApplication) {
        app.buttons["home_history_button"].tap()
        let deleteAll = app.navigationBars.buttons["すべて削除"]
        if deleteAll.waitForExistence(timeout: 2) {
            deleteAll.tap()
            let confirm = app.alerts.buttons["すべて削除"]
            if confirm.waitForExistence(timeout: 3) { confirm.tap() }
            sleep(1)
        }
        closeSheet(app)
        sleep(1)
    }

    private func closeSheet(_ app: XCUIApplication) {
        let close = app.navigationBars.buttons.matching(NSPredicate(format: "label == '閉じる' OR label == 'Close'")).firstMatch
        if close.waitForExistence(timeout: 3) { close.tap() } else { app.swipeDown() }
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let screenshot = app.windows.firstMatch.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
    }
}
