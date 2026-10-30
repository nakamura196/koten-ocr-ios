import XCTest
@testable import KotenOCR

final class LineTagLayoutTests: XCTestCase {

    func testVerticalLineTagSitsAboveTheBox() {
        let box = CGRect(x: 100, y: 50, width: 10, height: 200)
        let c = LineTagLayout.centers(for: [box])[0]
        XCTAssertEqual(c.x, box.midX, accuracy: 0.001)
        XCTAssertLessThan(c.y, box.minY)
    }

    func testHorizontalLineTagSitsLeftOfTheBox() {
        let box = CGRect(x: 60, y: 50, width: 200, height: 12)
        let c = LineTagLayout.centers(for: [box])[0]
        XCTAssertLessThan(c.x, box.minX)
        XCTAssertEqual(c.y, box.midY, accuracy: 0.001)
    }

    func testNeighbouringNarrowColumnsDoNotOverlap() {
        // Columns 8pt apart are narrower than a two-digit tag.
        let boxes = (0..<12).map { CGRect(x: 300 - CGFloat($0) * 8, y: 60, width: 7, height: 200) }
        let centers = LineTagLayout.centers(for: boxes)
        let tags = centers.enumerated().map { i, c -> CGRect in
            let s = LineTagLayout.size(for: i + 1)
            return CGRect(x: c.x - s.width / 2, y: c.y - s.height / 2, width: s.width, height: s.height)
        }
        for i in tags.indices { for j in tags.indices where j > i {
            XCTAssertFalse(tags[i].intersects(tags[j]), "tags \(i + 1) and \(j + 1) overlap")
        } }
        XCTAssertTrue(tags.allSatisfy { $0.maxY <= 60 })
    }

    func testFallsBackInsideWhenNoRoomAtTheTop() {
        let box = CGRect(x: 100, y: 2, width: 10, height: 200)
        let c = LineTagLayout.centers(for: [box])[0]
        XCTAssertGreaterThan(c.y, box.minY)
    }
}
