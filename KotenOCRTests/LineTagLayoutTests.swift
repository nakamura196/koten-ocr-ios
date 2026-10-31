import XCTest
@testable import KotenOCR

final class LineTagLayoutTests: XCTestCase {

    private let page = CGRect(x: 0, y: 0, width: 400, height: 300)

    func testVerticalLineTagSitsAboveTheBox() {
        let box = CGRect(x: 100, y: 50, width: 30, height: 200)
        let tag = LineTagLayout.frames(for: [box], in: page)[0]
        XCTAssertEqual(tag.midX, box.midX, accuracy: 0.001)
        XCTAssertLessThanOrEqual(tag.maxY, box.minY)
        XCTAssertEqual(tag.height, LineTagLayout.regularHeight, "wide columns keep the regular size")
    }

    func testHorizontalLineTagSitsLeftOfTheBox() {
        let box = CGRect(x: 60, y: 50, width: 200, height: 14)
        let tag = LineTagLayout.frames(for: [box], in: page)[0]
        XCTAssertLessThanOrEqual(tag.maxX, box.minX)
        XCTAssertEqual(tag.midY, box.midY, accuracy: 0.001)
    }

    /// Crowded pages (the Modern sample's left page, the Genji sample's columns): every tag
    /// stays at the start of its own line and no wider than it, so neighbours do not collide.
    func testNarrowColumnsKeepSmallTagsAboveEachColumn() {
        let boxes = (0..<12).map { CGRect(x: 300 - CGFloat($0) * 8, y: 60, width: 7, height: 200) }
        let tags = LineTagLayout.frames(for: boxes, in: page)
        for (i, (tag, box)) in zip(tags, boxes).enumerated() {
            XCTAssertLessThanOrEqual(tag.width, box.width + 0.001, "tag \(i + 1) is wider than its line")
            XCTAssertEqual(tag.midX, box.midX, accuracy: 0.001)
            XCTAssertLessThanOrEqual(tag.maxY, box.minY)
        }
        for i in tags.indices { for j in tags.indices where j > i {
            XCTAssertFalse(tags[i].intersects(tags[j]), "tags \(i + 1) and \(j + 1) overlap")
        } }
    }

    /// Two-digit tags are shrunk most; the gap to the box must not shrink with them.
    func testSmallTwoDigitTagsKeepTheFullGap() {
        let columns = (0..<12).map { CGRect(x: 300 - CGFloat($0) * 8, y: 60, width: 7, height: 200) }
        let tag = LineTagLayout.frames(for: columns, in: page)[11]
        XCTAssertLessThanOrEqual(tag.maxY, columns[11].minY - LineTagLayout.gap + 0.001)
        let lines = (0..<12).map { CGRect(x: 40, y: 40 + CGFloat($0) * 9, width: 150, height: 8) }
        let rowTag = LineTagLayout.frames(for: lines, in: page)[11]
        XCTAssertLessThanOrEqual(rowTag.maxX, lines[11].minX - LineTagLayout.gap + 0.001)
    }

    func testTightHorizontalLinesKeepSmallTagsLeftOfEachLine() {
        let boxes = (0..<8).map { CGRect(x: 40, y: 40 + CGFloat($0) * 9, width: 150, height: 8) }
        let tags = LineTagLayout.frames(for: boxes, in: page)
        for (tag, box) in zip(tags, boxes) {
            XCTAssertLessThanOrEqual(tag.height, box.height + 0.001)
            XCTAssertLessThanOrEqual(tag.maxX, box.minX)
            XCTAssertEqual(tag.midY, box.midY, accuracy: 0.001)
        }
    }

    /// A thin side note (傍書) between regular columns: its tag grows to the page's typical size
    /// where there is room, and still covers no box or other tag.
    func testThinSideNoteTagGrowsToTheTypicalSize() {
        let columns = (0..<5).map { CGRect(x: 320 - CGFloat($0) * 50, y: 40, width: 20, height: 220) }
        let note = CGRect(x: 297, y: 80, width: 4, height: 60)   // between the first two columns, starting lower
        let boxes = columns + [note]
        let tags = LineTagLayout.frames(for: boxes, in: page)
        XCTAssertEqual(tags[5].height, tags[0].height, accuracy: 0.001)
        XCTAssertEqual(tags[5].midX, note.midX, accuracy: 0.001)
        XCTAssertLessThanOrEqual(tags[5].maxY, note.minY - LineTagLayout.gap + 0.001)
        for (i, box) in boxes.enumerated() { XCTAssertFalse(tags[5].intersects(box), "covers box \(i + 1)") }
        for i in 0..<5 { XCTAssertFalse(tags[5].intersects(tags[i]), "overlaps tag \(i + 1)") }
    }

    /// A side note squeezed against a column keeps a tag no wider than the gap allows.
    func testSideNoteTagStaysSmallWithoutRoom() {
        let column = CGRect(x: 100, y: 40, width: 20, height: 220)
        let other = CGRect(x: 160, y: 40, width: 20, height: 220)
        let note = CGRect(x: 121, y: 48, width: 4, height: 60)   // touching the column, a larger tag would cover it
        let tags = LineTagLayout.frames(for: [column, other, note], in: page)
        XCTAssertFalse(tags[2].intersects(column))
        XCTAssertFalse(tags[2].intersects(tags[0]))
        XCTAssertLessThan(tags[2].height, tags[0].height)
    }

    func testFallsBackInsideWhenNoRoomAtTheTop() {
        let box = CGRect(x: 100, y: 2, width: 30, height: 200)
        let tag = LineTagLayout.frames(for: [box], in: page)[0]
        XCTAssertGreaterThanOrEqual(tag.minY, box.minY)
        XCTAssertTrue(page.contains(tag))
    }

    func testBoxLinesFollowTheLineThickness() {
        let narrow = (0..<5).map { CGRect(x: CGFloat($0) * 13, y: 0, width: 12, height: 200) }
        XCTAssertEqual(LineTagLayout.boxLineWidth(for: narrow), 0.96, accuracy: 0.001)
        let wide = [CGRect(x: 0, y: 0, width: 300, height: 40)]
        XCTAssertEqual(LineTagLayout.boxLineWidth(for: wide), 1.5)
        let tiny = [CGRect(x: 0, y: 0, width: 3, height: 50)]
        XCTAssertEqual(LineTagLayout.boxLineWidth(for: tiny), 0.5)
    }
}
