import XCTest
import UIKit

/// Regression for the App Store report "1枚ぐらいなら読み取ってくれますが、2枚目ぐらいで解析すると落ちます"
/// (1.3.5): two OCR runs in a row on 48 MP photos, the second in the other mode.
final class SecondImageTests: XCTestCase {

    private var app: XCUIApplication!

    private static let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Resources")

    /// Writes `name` upscaled to 6048×8064 (48 MP) as JPEG into the runner's temp directory.
    private func largeCopy(of name: String) throws -> String {
        let src = Self.resources.appendingPathComponent(name)
        let image = try XCTUnwrap(UIImage(contentsOfFile: src.path), "missing \(src.path)")
        let size = CGSize(width: 6048, height: 8064)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let data = UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.85) { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        let out = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("48mp_\(name)")
        try data.write(to: out)
        return out.path
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "YES", "-ocrSuccessCount", "999", "-skipHome", "YES",
                                "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
    }

    func testTwoSuccessiveOCRsOn48MPImages() throws {
        app.launchEnvironment["TEST_IMAGE_PATH"] = try largeCopy(of: "test_koten_sample.jpg")
        app.launchEnvironment["TEST_SECOND_IMAGE_PATH"] = try largeCopy(of: "test_ndl_sample.jpg")
        app.launch()

        let back = app.buttons["back_button"]
        XCTAssertTrue(back.waitForExistence(timeout: 300), "1st OCR result should appear")

        // Result → Back (confirm screen) → Cancel (camera) → 2nd image is loaded into the crop screen
        back.tap()
        let cancel = app.buttons.matching(NSPredicate(format: "label == 'キャンセル' OR label == 'Cancel'")).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        cancel.tap()

        let skip = app.buttons["skip_crop_button"]
        XCTAssertTrue(skip.waitForExistence(timeout: 60), "crop screen should show the 2nd image")
        skip.tap()

        let ndl = app.buttons["ndl_ocr_button"]
        XCTAssertTrue(ndl.waitForExistence(timeout: 10))
        ndl.tap()

        XCTAssertTrue(back.waitForExistence(timeout: 300), "2nd OCR result should appear")
        XCTAssertEqual(app.state, .runningForeground, "app should still be running after the 2nd OCR")
    }
}
