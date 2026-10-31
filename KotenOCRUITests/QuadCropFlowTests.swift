import XCTest

/// Four-corner crop → confirm → result. Optional (TEST_RUNNER_QUAD_SHOT_DIR): save each screen.
final class QuadCropFlowTests: XCTestCase {

    private let shotDir = ProcessInfo.processInfo.environment["QUAD_SHOT_DIR"] ?? ""
    private var sampleImage: String {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Resources/test_koten_sample.jpg").path
    }

    func testQuadCropShowsRectifiedPageOnConfirm() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "YES", "-ocrSuccessCount", "999",
                                "-coachShutterShown", "YES", "-coachCropCornerShown", "YES",
                                "-skipHome", "YES", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchEnvironment["TEST_IMAGE_PATH"] = sampleImage
        app.launchEnvironment["TEST_SHOW_CROP"] = "YES"
        app.launch()

        let crop = app.buttons["crop_button"]
        XCTAssertTrue(crop.waitForExistence(timeout: 120))
        app.buttons["4点補正"].tap()
        let tl = app.descendants(matching: .any)["quad_handle_topLeft"]
        XCTAssertTrue(tl.waitForExistence(timeout: 5))
        sleep(2)
        save("quad_1_before_drag")
        // Pull the top-left corner well inside, making a strong trapezoid.
        let start = tl.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 90, dy: 70)))
        sleep(1)
        save("quad_2_after_drag")
        crop.tap()

        let run = app.buttons["run_ocr_button"]
        XCTAssertTrue(run.waitForExistence(timeout: 10))
        sleep(1)
        save("quad_3_confirm")
        run.tap()
        let back = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'back_button'")).firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 300))
        sleep(3)
        save("quad_4_result")
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
