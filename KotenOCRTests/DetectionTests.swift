import XCTest
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
}
