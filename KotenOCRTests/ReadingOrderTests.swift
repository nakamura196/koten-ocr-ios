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

    // MARK: - Degenerate pages (regression: pixel-sized mesh table)

    func testSingleZeroWidthBoxOnLargeImage() {
        // A box clamped at the right edge of a 48 MP image has zero width.
        let d = det(6048, 100, 6048, 8000, text: "Z")
        let start = CFAbsoluteTimeGetCurrent()
        let result = processor.process(detections: [d], imageWidth: 6048, imageHeight: 8064)
        XCTAssertEqual(result.map(\.text), ["Z"])
        XCTAssertLessThan(CFAbsoluteTimeGetCurrent() - start, 0.5)
    }

    func testBoxesInOneZeroWidthColumn() {
        let detections = [det(500, 3000, 500, 4000, text: "b"), det(500, 100, 500, 2000, text: "a")]
        let result = processor.process(detections: detections, imageWidth: 6048, imageHeight: 8064)
        XCTAssertEqual(Set(result.map(\.text)), ["a", "b"])
    }

    func testSingleVeryFlatBox() {
        let d = det(0, 4000, 8000, 4010, text: "flat")
        let start = CFAbsoluteTimeGetCurrent()
        let result = processor.process(detections: [d], imageWidth: 8064, imageHeight: 6048)
        XCTAssertEqual(result.map(\.text), ["flat"])
        XCTAssertLessThan(CFAbsoluteTimeGetCurrent() - start, 0.5)
    }

    // MARK: - Fragmented columns

    /// The tilted photo sample_shibata: one column was detected as a full-height box plus three fragments
    /// whose left edges differ by a few pixels. They end up in one XY-cut leaf, and sorting that leaf by
    /// the left edge alone put the bottom fragment before the top one. Lines whose centres are within
    /// 0.3 × the median width are one column (as NDLOCR-Lite's sort_lines_local) and read top to bottom.
    func testFragmentsOfOneColumnReadTopToBottom() {
        let detections = [
            det(536, 557, 605, 877, text: "middle"),
            det(532, 47, 589, 384, text: "top"),
            det(531, 718, 566, 873, text: "bottom"),
            det(530, 2, 604, 881, text: "whole"),
            det(567, 283, 599, 383, text: "side note"),
            det(540, 284, 572, 388, text: "side note 2"),
            det(440, 0, 504, 877, text: "next column"),
        ]
        let texts = processor.process(detections: detections, imageWidth: 700, imageHeight: 900).map(\.text)
        let fragments = texts.filter { ["top", "middle", "bottom"].contains($0) }
        XCTAssertEqual(fragments, ["top", "middle", "bottom"])
        XCTAssertEqual(texts.last, "next column")
    }
}
