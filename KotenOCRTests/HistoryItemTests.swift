import XCTest
@testable import KotenOCR

final class HistoryItemTests: XCTestCase {

    func testEncodeDecode() throws {
        let original = HistoryItem(
            id: UUID(),
            date: Date(timeIntervalSince1970: 1718430600), // fixed date
            text: "古典テキスト",
            detections: [
                Detection(box: [10, 20, 100, 200], score: 0.9, classId: 0, className: "text", text: "漢")
            ],
            imageFileName: "test.jpg",
            translatedText: "翻訳結果"
        )

        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(HistoryItem.self, from: data)

        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.date.timeIntervalSince1970, original.date.timeIntervalSince1970, accuracy: 1.0)
        XCTAssertEqual(restored.text, original.text)
        XCTAssertEqual(restored.detections.count, 1)
        XCTAssertEqual(restored.detections[0].text, "漢")
        XCTAssertEqual(restored.imageFileName, original.imageFileName)
        XCTAssertEqual(restored.translatedText, "翻訳結果")
    }

    func testDecodeWithNilTranslatedText() throws {
        let item = HistoryItem(
            id: UUID(),
            date: Date(),
            text: "",
            detections: [],
            imageFileName: "empty.jpg"
        )
        let data = try JSONEncoder().encode(item)
        let restored = try JSONDecoder().decode(HistoryItem.self, from: data)
        XCTAssertNil(restored.translatedText)
    }

    func testEmptyDetections() throws {
        let item = HistoryItem(
            id: UUID(),
            date: Date(),
            text: "",
            detections: [],
            imageFileName: "empty.jpg"
        )
        let data = try JSONEncoder().encode(item)
        let restored = try JSONDecoder().decode(HistoryItem.self, from: data)
        XCTAssertTrue(restored.detections.isEmpty)
    }

    func testMultipleDetections() throws {
        let item = HistoryItem(
            id: UUID(),
            date: Date(),
            text: "源氏",
            detections: [
                Detection(box: [10, 20, 30, 40], score: 0.95, classId: 0, className: "text", text: "源", id: 1),
                Detection(box: [50, 60, 70, 80], score: 0.87, classId: 0, className: "text", text: "氏", id: 2),
            ],
            imageFileName: "test.jpg"
        )
        let data = try JSONEncoder().encode(item)
        let restored = try JSONDecoder().decode(HistoryItem.self, from: data)
        XCTAssertEqual(restored.detections.count, 2)
        XCTAssertEqual(restored.detections[0].text, "源")
        XCTAssertEqual(restored.detections[1].text, "氏")
    }

    func testTranslatedTextIsMutable() {
        var item = HistoryItem(
            id: UUID(),
            date: Date(),
            text: "text",
            detections: [],
            imageFileName: "mut.jpg"
        )
        XCTAssertNil(item.translatedText)
        item.translatedText = "新しい翻訳"
        XCTAssertEqual(item.translatedText, "新しい翻訳")
    }
}
