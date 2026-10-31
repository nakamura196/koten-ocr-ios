import XCTest
import OnnxRuntimeBindings
@testable import KotenOCR

final class DetectionTests: XCTestCase {

    // MARK: - Codable Round-Trip

    func testEncodeDecode() throws {
        let original = Detection(
            box: [10, 20, 100, 200],
            score: 0.95,
            classId: 0,
            className: "text",
            text: "漢字",
            id: 5
        )
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(Detection.self, from: data)

        XCTAssertEqual(restored.box, original.box)
        XCTAssertEqual(restored.score, original.score)
        XCTAssertEqual(restored.classId, original.classId)
        XCTAssertEqual(restored.className, original.className)
        XCTAssertEqual(restored.text, original.text)
        XCTAssertEqual(restored.id, original.id)
    }

    func testDecodeWithDefaults() throws {
        // text and id have defaults; test that explicit JSON values still decode
        let json = """
        {"box":[0,0,50,50],"score":0.5,"classId":1,"className":"class_1","text":"","id":0}
        """.data(using: .utf8)!

        let d = try JSONDecoder().decode(Detection.self, from: json)
        XCTAssertEqual(d.text, "")
        XCTAssertEqual(d.id, 0)
    }

    func testDecodeFromJsonWithAllFields() throws {
        let json = """
        {
            "box": [5, 10, 150, 300],
            "score": 0.72,
            "classId": 0,
            "className": "text",
            "text": "古典",
            "id": 42
        }
        """.data(using: .utf8)!

        let d = try JSONDecoder().decode(Detection.self, from: json)
        XCTAssertEqual(d.box, [5, 10, 150, 300])
        XCTAssertEqual(d.score, 0.72, accuracy: 0.001)
        XCTAssertEqual(d.text, "古典")
        XCTAssertEqual(d.id, 42)
    }

    func testTextIsMutable() {
        var d = Detection(box: [0, 0, 10, 10], score: 0.9, classId: 0, className: "text")
        XCTAssertEqual(d.text, "")
        d.text = "修正後"
        XCTAssertEqual(d.text, "修正後")
    }

    // MARK: - Box clamping

    func testClampedBoxKeepsBoxesInsideTheImage() {
        XCTAssertEqual(Detection.clampedBox(-5.4, 10.6, 120.5, 90, width: 100, height: 80,
                                            rounding: .toNearestOrAwayFromZero), [0, 11, 100, 80])
        XCTAssertEqual(Detection.clampedBox(10.9, 10.9, 50.9, 50.9, width: 100, height: 80,
                                            rounding: .towardZero), [10, 10, 50, 50])
    }

    func testClampedBoxDropsBoxesWithNothingInside() {
        XCTAssertNil(Detection.clampedBox(-30, -20, -5, -2, width: 100, height: 80, rounding: .towardZero))
        XCTAssertNil(Detection.clampedBox(150, 10, 190, 30, width: 100, height: 80, rounding: .towardZero))
        XCTAssertNil(Detection.clampedBox(.nan, 10, 50, 30, width: 100, height: 80, rounding: .towardZero))
    }

    /// RTMDet (koten) boxes were clamped only on one side each, so a box above the page or past its
    /// right edge came out with negative or inverted coordinates.
    func testRTMDetectorDropsBoxesOutsideThePage() throws {
        guard let path = Bundle.main.path(forResource: "rtmdet-s-1280x1280", ofType: "onnx", inDirectory: "Models") else {
            throw XCTSkip("Models not available")
        }
        let detector = try RTMDetector(env: try ORTEnv(loggingLevel: .warning), modelPath: path)
        var dets: [Float] = [-40, -60, -10, -20, 0.9,   1100, 100, 1200, 400, 0.9,   100, 100, 150, 400, 0.9]
        var labels: [Int64] = [0, 0, 0]
        let outputs: [String: ORTValue] = [
            "dets": try ORTValue(tensorData: NSMutableData(bytes: &dets, length: dets.count * 4), elementType: .float, shape: [1, 3, 5]),
            "labels": try ORTValue(tensorData: NSMutableData(bytes: &labels, length: labels.count * 8), elementType: .int64, shape: [1, 3])
        ]
        let result = try detector.postprocess(outputs: outputs,
                                              metadata: .init(originalWidth: 1024, originalHeight: 1024, maxWH: 1024))
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.allSatisfy { $0.box.allSatisfy { $0 >= 0 } && $0.box[2] > $0.box[0] && $0.box[3] > $0.box[1] })
    }
}
