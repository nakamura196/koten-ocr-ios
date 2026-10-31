import XCTest
@testable import KotenOCR

final class OCREngineTests: XCTestCase {

    // MARK: - OCREngineState

    func testInitialState() {
        let engine = OCREngine()
        if case .uninitialized = engine.state {
            // pass
        } else {
            XCTFail("Expected .uninitialized state, got \(engine.state)")
        }
    }

    func testInitialProgress() {
        let engine = OCREngine()
        XCTAssertEqual(engine.progress, 0)
    }

    // MARK: - OCRResult

    func testOCRResultConstruction() {
        let detections = [
            Detection(box: [0, 0, 50, 50], score: 0.9, classId: 0, className: "text", text: "あ"),
            Detection(box: [60, 0, 110, 50], score: 0.8, classId: 0, className: "text", text: "い"),
        ]
        let result = OCRResult(detections: detections, text: "あ\nい")
        XCTAssertEqual(result.detections.count, 2)
        XCTAssertEqual(result.text, "あ\nい")
    }

    func testOCRResultEmpty() {
        let result = OCRResult(detections: [], text: "")
        XCTAssertTrue(result.detections.isEmpty)
        XCTAssertEqual(result.text, "")
    }

    // MARK: - Mode switching

    /// A switch whose models cannot be loaded (here: no ONNX Runtime environment yet) must leave the
    /// engine on the mode it can still run.
    func testFailedModeSwitchKeepsThePreviousMode() async {
        let key = "ocrMode"
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
        let engine = OCREngine()
        engine.currentModeRaw = OCRMode.koten.rawValue
        do {
            try await engine.switchMode(to: .ndl)
            XCTFail("switching without loaded models should throw")
        } catch {}
        XCTAssertEqual(engine.currentMode, .koten)
    }

    // MARK: - Line direction

    func testPageDirectionIsTheMajorityOfLines() {
        let tall = Detection(box: [0, 0, 20, 200], score: 0.9, classId: 0, className: "text")
        let wide = Detection(box: [0, 0, 200, 20], score: 0.9, classId: 0, className: "text")
        XCTAssertTrue(OCREngine.isVerticalPage([tall, tall, wide]))
        XCTAssertFalse(OCREngine.isVerticalPage([tall, wide, wide]))
    }

    /// One or two characters (a near-square box) follow the page; long boxes follow their own shape.
    func testShortBoxesFollowThePageDirection() {
        // A single wide kana on a vertical page is still read as vertical text.
        XCTAssertTrue(OCREngine.readsVertically(box: [100, 100, 160, 150], pageVertical: true))
        // A narrow "1" on a horizontal page is read horizontally (it used to be rotated).
        XCTAssertFalse(OCREngine.readsVertically(box: [100, 100, 120, 128], pageVertical: false))
        // Long lines keep their own direction whatever the page.
        XCTAssertTrue(OCREngine.readsVertically(box: [100, 100, 130, 400], pageVertical: false))
        XCTAssertFalse(OCREngine.readsVertically(box: [100, 100, 400, 130], pageVertical: true))
    }
}
