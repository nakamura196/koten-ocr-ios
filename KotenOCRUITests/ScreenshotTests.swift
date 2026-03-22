import XCTest

/// Automated screenshot capture for App Store marketing images.
///
/// Uses TEST_IMAGE_PATH env var to auto-load an image, bypassing PHPicker.
/// Run: ./scripts/capture_screenshots.sh
final class ScreenshotTests: XCTestCase {

    private var app: XCUIApplication!
    private let screenshotDir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"]
        ?? "/tmp/kotenocr_screenshots"
    private let projectRoot = "/Users/nakamura/git/hi/miyako/koten-ocr-ios"

    // Path to test image for 古典籍 (kuzushiji) mode
    private var testImagePath: String {
        if let envPath = ProcessInfo.processInfo.environment["TEST_IMAGE_PATH"],
           !envPath.isEmpty {
            return envPath
        }
        return "\(projectRoot)/KotenOCRUITests/Resources/test_koten_sample.jpg"
    }

    // Path to test image for 近代 (NDL) mode — 校異源氏物語
    private var testNDLImagePath: String {
        return "\(projectRoot)/KotenOCRUITests/Resources/test_ndl_sample.jpg"
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

    /// Demo video flow (古典籍 mode, auto-load): camera → OCR result → scroll → translation
    /// Optimized for 30-second App Store preview.
    /// Run with `xcrun simctl io <UDID> recordVideo` to capture.
    func testDemoVideoFlow() throws {
        // Show camera screen briefly, then relaunch with auto-load
        app.launchEnvironment["TEST_IMAGE_PATH"] = ""
        app.launch()
        sleep(2)  // Brief camera view

        // Relaunch with test image to trigger OCR
        app.launchEnvironment["TEST_IMAGE_PATH"] = testImagePath
        app.launch()

        // Wait for OCR to complete
        let backButton = app.buttons.matching(
            NSPredicate(format: "identifier == 'back_button'")
        ).firstMatch
        let resultLoaded = backButton.waitForExistence(timeout: 300)
        XCTAssertTrue(resultLoaded, "OCR result should appear within 300s")
        sleep(2)  // Pause on OCR result

        // Scroll to show more results
        app.swipeUp()
        sleep(1)
        app.swipeDown()
        sleep(1)

        // Switch to translation tab
        let translationTab = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '現代語訳' OR label CONTAINS 'Translation'")
        ).firstMatch
        if translationTab.waitForExistence(timeout: 3) {
            translationTab.tap()
            sleep(2)  // Show translation
        }

        // Go back to camera
        backButton.tap()
        sleep(1)
    }

    /// Demo video flow: crop → select 近代 OCR → result → translation
    /// Uses 校異源氏物語 sample image for 近代 OCR mode.
    /// Single launch with TEST_SHOW_CROP to go directly to crop flow (no restart).
    /// Optimized for 30-second App Store preview.
    func testDemoVideoPickerFlow() throws {
        // Single launch: load 校異源氏物語 image directly into crop flow
        app.launchEnvironment["TEST_IMAGE_PATH"] = testNDLImagePath
        app.launchEnvironment["TEST_SHOW_CROP"] = "YES"
        app.launch()

        // Crop screen appears — skip cropping
        let skipButton = app.buttons["skip_crop_button"]
        XCTAssertTrue(skipButton.waitForExistence(timeout: 60), "Crop screen should appear")
        sleep(2)  // Show crop screen briefly
        skipButton.tap()

        // Confirm screen — select 近代 OCR mode
        let ndlButton = app.buttons["ndl_ocr_button"]
        XCTAssertTrue(ndlButton.waitForExistence(timeout: 10), "OCR mode buttons should appear")
        sleep(1)  // Show mode selection briefly
        ndlButton.tap()

        // Wait for OCR to complete
        let backButton = app.buttons.matching(
            NSPredicate(format: "identifier == 'back_button'")
        ).firstMatch
        let resultLoaded = backButton.waitForExistence(timeout: 300)
        XCTAssertTrue(resultLoaded, "OCR result should appear within 300s")
        sleep(2)  // Pause on OCR result

        // Scroll to show results
        app.swipeUp()
        sleep(1)
        app.swipeDown()
        sleep(1)

        // Switch to translation tab
        let translationTab = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '現代語訳' OR label CONTAINS 'Translation'")
        ).firstMatch
        if translationTab.waitForExistence(timeout: 3) {
            translationTab.tap()
            sleep(2)  // Show translation
        }

        // Go back to camera
        backButton.tap()
        sleep(1)
    }

    /// Combined demo: 古典籍 OCR → 近代 OCR in a single video.
    /// 1st image (kuzushiji) auto-processed, 2nd image (校異源氏物語) via crop + mode selection.
    /// Optimized for 30-second App Store preview.
    func testDemoVideoCombined() throws {
        // Launch with koten image (auto-process) + NDL image queued for second load
        app.launchEnvironment["TEST_IMAGE_PATH"] = testImagePath
        app.launchEnvironment["TEST_SECOND_IMAGE_PATH"] = testNDLImagePath
        app.launch()

        // Wait for 古典籍 OCR result
        let backButton = app.buttons.matching(
            NSPredicate(format: "identifier == 'back_button'")
        ).firstMatch
        let resultLoaded = backButton.waitForExistence(timeout: 300)
        XCTAssertTrue(resultLoaded, "1st OCR result should appear")
        sleep(2)  // Show 古典籍 result

        // Show translation for 古典籍
        let translationTab = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '現代語訳' OR label CONTAINS 'Translation'")
        ).firstMatch
        if translationTab.waitForExistence(timeout: 3) {
            translationTab.tap()
            sleep(2)  // Show translation
        }

        // Back to confirmCrop, then cancel to camera → triggers second image load
        backButton.tap()
        sleep(1)
        // Tap cancel to go back to camera
        let cancelButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Cancel' OR label CONTAINS 'キャンセル'")
        ).firstMatch
        if cancelButton.waitForExistence(timeout: 3) {
            cancelButton.tap()
        }

        // Crop screen appears with 校異源氏物語 image — skip cropping
        let skipButton = app.buttons["skip_crop_button"]
        XCTAssertTrue(skipButton.waitForExistence(timeout: 30), "Crop screen should appear with 2nd image")
        sleep(1)
        skipButton.tap()

        // Select 近代 OCR mode
        let ndlButton = app.buttons["ndl_ocr_button"]
        XCTAssertTrue(ndlButton.waitForExistence(timeout: 10), "OCR mode buttons should appear")
        sleep(1)
        ndlButton.tap()

        // Wait for 近代 OCR result
        let resultLoaded2 = backButton.waitForExistence(timeout: 300)
        XCTAssertTrue(resultLoaded2, "2nd OCR result should appear")
        sleep(2)  // Show 近代 result

        // Scroll briefly
        app.swipeUp()
        sleep(1)
        app.swipeDown()
        sleep(1)

        // Back to camera
        backButton.tap()
        sleep(1)
        if cancelButton.waitForExistence(timeout: 3) {
            cancelButton.tap()
        }
        sleep(1)
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
