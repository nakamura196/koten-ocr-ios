import XCTest

/// Automated screenshot capture for App Store marketing images.
///
/// Uses TEST_IMAGE_PATH env var to auto-load an image, bypassing PHPicker.
/// Run: ./scripts/capture_screenshots.sh
final class ScreenshotTests: XCTestCase {

    private var app: XCUIApplication!
    private let screenshotDir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"]
        ?? "/tmp/kotenocr_screenshots"
    // Path to test image - defaults to the bundled sample in the project
    private var testImagePath: String {
        if let envPath = ProcessInfo.processInfo.environment["TEST_IMAGE_PATH"],
           !envPath.isEmpty {
            return envPath
        }
        // Default: find the project root from the test bundle location
        // The test image is at KotenOCRUITests/Resources/test_koten_sample.jpg
        let bundle = Bundle(for: type(of: self))
        let testBundlePath = bundle.bundlePath
        // Navigate from .xctest bundle to project root
        // DerivedData/.../Debug-iphonesimulator/KotenOCRUITests-Runner.app/PlugIns/KotenOCRUITests.xctest
        // We need to use a fixed known path instead
        return "/Users/nakamura/git/hi/miyako/koten-ocr-ios/KotenOCRUITests/Resources/test_koten_sample.jpg"
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "YES", "-ocrSuccessCount", "999"]

        // Match app language to the test runner language (set by xcodebuild -testLanguage)
        let preferredLang = Locale.preferredLanguages.first ?? "ja"
        let langCode = preferredLang.components(separatedBy: "-").first ?? "ja"
        app.launchArguments += ["-AppleLanguages", "(\(langCode))", "-AppleLocale", langCode]
        // Pass test image path and dummy translation to the app via environment
        app.launchEnvironment["TEST_IMAGE_PATH"] = testImagePath
        app.launchEnvironment["TEST_TRANSLATION_TEXT"] = """
【現代語訳】
いつの時代のことか、女たちがたくさん仕えていた中に、とても高貴な方がいらっしゃった。その方は「私は」と言っておられ、また「秋だと思う」と言っておられた。明るく輝くその姿は、目を見張るようなもので、他の更衣たちが嫉妬している様子が見受けられた。ましてや、朝夕の宮仕えにおいては、人々の心に何かしらの恨みを抱かせるようなことがあったのだろうか。いとあつくなっていく心は、ますます細くなり、哀しみを感じるようになっていった。人々の非難をも受け入れられず、世の中の例に従うことができなかった。

【解説】
この文章は、平安時代の文学作品である『源氏物語』の一部と考えられます。平安時代は、貴族文化が栄え、恋愛や人間関係の複雑さが描かれた時代です。この文章では、宮中の女たちの嫉妬や心の葛藤が表現されており、特に高貴な女性に対する感情が描かれています。
"""
        try FileManager.default.createDirectory(
            atPath: screenshotDir,
            withIntermediateDirectories: true
        )
    }

    /// Capture OCR result screenshot by auto-loading test image
    func testCaptureOCRResult() throws {
        XCTAssertFalse(testImagePath.isEmpty, "TEST_IMAGE_PATH must be set")
        app.launch()

        // Wait for OCR to complete (models load + auto-process test image)
        let backButton = app.buttons.matching(
            NSPredicate(format: "identifier == 'back_button'")
        ).firstMatch
        let resultLoaded = backButton.waitForExistence(timeout: 300)
        XCTAssertTrue(resultLoaded, "OCR result should appear within 300s")
        sleep(2)

        // Screenshot: OCR result
        saveScreenshot(name: "04_result")

        // Try translation tab
        let translationTab = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '現代語訳' OR label CONTAINS 'Translation'")
        ).firstMatch
        if translationTab.waitForExistence(timeout: 3) {
            translationTab.tap()
            sleep(1)
            saveScreenshot(name: "05_translation")
        }

        // Go back to camera
        backButton.tap()
        sleep(1)

        // Screenshot: Camera view
        saveScreenshot(name: "01_camera")

        // Screenshot: Settings
        let settingsButton = app.buttons.matching(
            NSPredicate(format: "identifier == 'settings_button'")
        ).firstMatch
        if settingsButton.waitForExistence(timeout: 5) {
            settingsButton.tap()
            sleep(1)
            saveScreenshot(name: "06_settings")
        }
    }

    /// Demo video flow: camera → OCR result → scroll → translation → back → settings
    /// Run with `xcrun simctl io <UDID> recordVideo` to capture as App Store preview.
    func testDemoVideoFlow() throws {
        // Show camera screen briefly, then relaunch with auto-load
        app.launchEnvironment["TEST_IMAGE_PATH"] = ""
        app.launch()
        sleep(3)  // Show camera screen for video

        // Relaunch with test image to trigger OCR
        app.launchEnvironment["TEST_IMAGE_PATH"] = testImagePath
        app.launch()

        // Wait for OCR to complete
        let backButton = app.buttons.matching(
            NSPredicate(format: "identifier == 'back_button'")
        ).firstMatch
        let resultLoaded = backButton.waitForExistence(timeout: 300)
        XCTAssertTrue(resultLoaded, "OCR result should appear within 300s")
        sleep(3)  // Pause on OCR result

        // Scroll down to show more results
        app.swipeUp()
        sleep(2)
        app.swipeDown()
        sleep(1)

        // Switch to translation tab
        let translationTab = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '現代語訳' OR label CONTAINS 'Translation'")
        ).firstMatch
        if translationTab.waitForExistence(timeout: 3) {
            translationTab.tap()
            sleep(3)  // Show translation
        }

        // Go back to camera
        backButton.tap()
        sleep(2)

        // Open settings
        let settingsButton = app.buttons.matching(
            NSPredicate(format: "identifier == 'settings_button'")
        ).firstMatch
        if settingsButton.waitForExistence(timeout: 5) {
            settingsButton.tap()
            sleep(3)  // Show settings

            // Close settings
            let closeButton = app.buttons.matching(
                NSPredicate(format: "identifier == 'close_button' OR label == '閉じる' OR label == 'Close'")
            ).firstMatch
            if closeButton.waitForExistence(timeout: 3) {
                closeButton.tap()
            }
        }
        sleep(2)  // End on camera screen
    }

    /// Capture onboarding screenshots
    func testCaptureOnboarding() throws {
        app.launchArguments = ["-hasCompletedOnboarding", "NO"]
        app.launchEnvironment["TEST_IMAGE_PATH"] = ""
        app.launch()
        sleep(3)

        saveScreenshot(name: "07_onboarding_intro")
        app.swipeLeft()
        sleep(1)
        saveScreenshot(name: "08_onboarding_howto")
    }

    // MARK: - Helpers

    private func saveScreenshot(name: String) {
        let screenshot = app.windows.firstMatch.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let path = "\(screenshotDir)/\(name).png"
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: path))
        print("Screenshot saved: \(path)")
    }
}
