import XCTest

/// Edit boxes: enter, select, delete, undo, cancel. Opens the result with TEST_IMAGE_PATH like ScreenshotTests.
/// Set BOX_EDIT_SHOT_DIR to also write PNGs of each step.
final class BoxEditUITests: XCTestCase {

    private var app: XCUIApplication!
    private let projectRoot = "/Users/nakamura/git/hi/miyako/koten-ocr-ios"
    private let shotDir = ProcessInfo.processInfo.environment["BOX_EDIT_SHOT_DIR"] ?? ""

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "YES", "-ocrSuccessCount", "999", "-skipHome", "YES",
                                "-coachShutterShown", "YES", "-coachCropCornerShown", "YES",
                                "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        let path = ProcessInfo.processInfo.environment["TEST_IMAGE_PATH"].flatMap { $0.isEmpty ? nil : $0 }
            ?? "\(projectRoot)/KotenOCRUITests/Resources/test_koten_sample.jpg"
        app.launchEnvironment["TEST_IMAGE_PATH"] = path
        if !shotDir.isEmpty { try FileManager.default.createDirectory(atPath: shotDir, withIntermediateDirectories: true) }
        app.launch()
        XCTAssertTrue(app.buttons["back_button"].waitForExistence(timeout: 300), "OCR result should appear")
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func shot(_ name: String) {
        guard !shotDir.isEmpty else { return }
        let s = app.windows.firstMatch.screenshot()
        try? s.pngRepresentation.write(to: URL(fileURLWithPath: "\(shotDir)/\(name).png"))
    }

    /// "Fix boxes" now lives in the result screen's "…" menu.
    private func enterEditMode() {
        let more = app.buttons["result_more_menu"]
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        more.tap()
        let enter = app.buttons["box_edit_enter"]
        XCTAssertTrue(enter.waitForExistence(timeout: 10))
        enter.tap()
        XCTAssertTrue(app.buttons["box_edit_done"].waitForExistence(timeout: 5))
    }

    func testSelectDeleteUndoCancel() throws {
        let row0 = element("detection_row_0")
        XCTAssertTrue(row0.waitForExistence(timeout: 10))
        let original = row0.label
        XCTAssertFalse(original.isEmpty)

        enterEditMode()
        XCTAssertTrue(app.buttons["box_tool_select"].exists)
        XCTAssertFalse(app.buttons["box_edit_delete"].isEnabled, "nothing selected yet")
        // While editing, the header and the line list make way for the page.
        XCTAssertFalse(app.buttons["back_button"].exists, "header is hidden while editing")
        XCTAssertFalse(row0.exists, "line list is hidden while editing")
        let bar = element("box_edit_selected_line")
        XCTAssertTrue(bar.exists)
        let total = bar.value as? String
        shot("01_edit_mode")

        // Select the first box with › ; the bar shows its text like the row did.
        app.buttons["box_edit_next"].tap()
        XCTAssertEqual(bar.label, original)
        let delete = app.buttons["box_edit_delete"]
        XCTAssertTrue(delete.isEnabled)
        shot("02_selected")

        delete.tap()
        XCTAssertNotEqual(bar.value as? String, total, "one line fewer")
        let undo = app.buttons["box_edit_undo"]
        XCTAssertTrue(undo.isEnabled)
        shot("03_deleted")

        undo.tap()
        XCTAssertEqual(bar.value as? String, total)
        XCTAssertFalse(undo.isEnabled, "undo stack is empty again")

        // Delete once more, then Cancel must restore the original.
        app.buttons["box_edit_next"].tap()
        delete.tap()
        XCTAssertNotEqual(bar.value as? String, total)
        app.buttons["box_edit_cancel"].tap()
        XCTAssertTrue(app.buttons["result_more_menu"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["back_button"].exists, "header is back")
        XCTAssertEqual(element("detection_row_0").label, original)
    }

    /// Draws, splits and re-reads with real touches; writes screenshots when BOX_EDIT_SHOT_DIR is set.
    func testAddSplitAndReread() throws {
        enterEditMode()
        let stage = element("box_edit_stage")
        XCTAssertTrue(stage.waitForExistence(timeout: 5))

        // Add a box by dragging on the image.
        app.buttons["box_tool_add"].tap()
        let from = stage.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: 0.30))
        let to = stage.coordinate(withNormalizedOffset: CGVector(dx: 0.38, dy: 0.62))
        from.press(forDuration: 0.1, thenDragTo: to)
        shot("04_added")
        let reread = app.buttons["box_edit_reread"]
        XCTAssertTrue(reread.isEnabled, "the new box is waiting to be read")
        XCTAssertTrue(app.buttons["box_edit_undo"].isEnabled)

        reread.tap()
        let deadline = Date().addingTimeInterval(60)
        while reread.isEnabled && Date() < deadline { usleep(300_000) }
        XCTAssertFalse(reread.isEnabled, "nothing left to read")
        shot("05_reread")

        // Split: tap in the middle of the image area with the Split tool.
        app.buttons["box_tool_split"].tap()
        stage.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        shot("06_split")
        app.buttons["box_tool_merge"].tap()
        shot("07_merge_tool")
        app.buttons["box_edit_cancel"].tap()
        XCTAssertTrue(app.buttons["result_more_menu"].waitForExistence(timeout: 5))
    }
    /// Selects a line, drags inside it and pinches the page; screenshots show the colours,
    /// the side and corner grips and the zoomed page (BOX_EDIT_SHOT_DIR).
    func testSelectDragAndZoom() throws {
        enterEditMode()
        let stage = element("box_edit_stage")
        XCTAssertTrue(stage.waitForExistence(timeout: 5))
        shot("10_colours")
        app.buttons["box_edit_next"].tap()
        XCTAssertTrue(app.buttons["box_edit_delete"].isEnabled)
        shot("11_selected_grips")
        XCTAssertEqual(stage.value as? String, "fit")
        stage.pinch(withScale: 2.5, velocity: 2)
        XCTAssertEqual(stage.value as? String, "zoomed")
        shot("12_zoomed")
        // Double tap while editing goes back to the whole page (it used to only select a line).
        stage.doubleTap()
        sleep(1)   // zoom animates for 0.3 s
        XCTAssertEqual(stage.value as? String, "fit", "double tap should return to the whole page")
        shot("13_zoom_reset")
        // And zooms in again from the whole page.
        stage.doubleTap()
        sleep(1)
        XCTAssertEqual(stage.value as? String, "zoomed")
        shot("14_double_tap_zoom")
        app.buttons["box_edit_cancel"].tap()
        XCTAssertTrue(app.buttons["result_more_menu"].waitForExistence(timeout: 5))
    }
}
