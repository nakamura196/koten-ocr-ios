import XCTest
@testable import KotenOCR

final class ReadingOrderTests: XCTestCase {

    private var processor: ReadingOrderProcessor!

    override func setUp() {
        super.setUp()
        processor = ReadingOrderProcessor()
    }

    private func det(_ x1: Int, _ y1: Int, _ x2: Int, _ y2: Int, text: String = "") -> Detection {
        Detection(box: [x1, y1, x2, y2], score: 0.9, classId: 0, className: "text", text: text)
    }

    // MARK: - Edge Cases

    func testEmptyDetections() {
        let result = processor.process(detections: [], imageWidth: 1000, imageHeight: 1000)
        XCTAssertTrue(result.isEmpty)
    }

    func testSingleDetection() {
        let d = det(100, 100, 200, 130, text: "A")
        let result = processor.process(detections: [d], imageWidth: 1000, imageHeight: 1000)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].text, "A")
    }

    // MARK: - Horizontal Text

    func testHorizontalTextTopToBottom() {
        // Wide boxes (width > height) → horizontal text
        let detections = [
            det(50, 200, 400, 230, text: "line2"),
            det(50, 100, 400, 130, text: "line1"),
            det(50, 300, 400, 330, text: "line3"),
        ]
        let result = processor.process(detections: detections, imageWidth: 500, imageHeight: 500)
        let texts = result.map(\.text)
        XCTAssertEqual(texts, ["line1", "line2", "line3"])
    }

    // MARK: - Vertical Text

    func testVerticalTextRightToLeft() {
        // Tall boxes (height > width) → vertical text, right-to-left
        let detections = [
            det(100, 50, 130, 400, text: "col3"), // leftmost = last
            det(200, 50, 230, 400, text: "col2"),
            det(300, 50, 330, 400, text: "col1"), // rightmost = first
        ]
        let result = processor.process(detections: detections, imageWidth: 500, imageHeight: 500)
        let texts = result.map(\.text)
        XCTAssertEqual(texts, ["col1", "col2", "col3"])
    }

    // MARK: - Block Separation

    func testTwoBlocksHorizontal() {
        let top1 = det(50, 50, 400, 80, text: "top1")
        let top2 = det(50, 100, 400, 130, text: "top2")
        let bottom1 = det(50, 400, 400, 430, text: "bottom1")
        let bottom2 = det(50, 450, 400, 480, text: "bottom2")

        let detections = [bottom2, top1, bottom1, top2]
        let result = processor.process(detections: detections, imageWidth: 500, imageHeight: 600)
        let texts = result.map(\.text)

        // Top block should come before bottom block
        guard let top1Idx = texts.firstIndex(of: "top1"),
              let bottom1Idx = texts.firstIndex(of: "bottom1") else {
            XCTFail("Expected texts not found")
            return
        }
        XCTAssertLessThan(top1Idx, bottom1Idx)
    }

    // MARK: - Preservation

    func testPreservesAllDetections() {
        let detections = (0..<20).map { i in
            det(i * 10, i * 20, i * 10 + 50, i * 20 + 15, text: "\(i)")
        }
        let result = processor.process(detections: detections, imageWidth: 1000, imageHeight: 1000)
        XCTAssertEqual(result.count, 20)
    }

    // MARK: - Stress Test

    func testManyDetectionsDoNotCrash() {
        let detections = (0..<100).map { i in
            det(
                (i % 10) * 100,
                (i / 10) * 50,
                (i % 10) * 100 + 80,
                (i / 10) * 50 + 15,
                text: "box\(i)"
            )
        }
        let result = processor.process(detections: detections, imageWidth: 1200, imageHeight: 600)
        XCTAssertEqual(result.count, 100)
    }
}
