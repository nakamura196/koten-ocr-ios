import XCTest
@testable import KotenOCR

final class BoxEditorTests: XCTestCase {

    private func det(_ x1: Int, _ y1: Int, _ x2: Int, _ y2: Int, _ text: String) -> Detection {
        Detection(box: [x1, y1, x2, y2], score: 0.9, classId: 0, className: "text", text: text, predCharCount: 3)
    }

    private func makeEditor() -> BoxEditor {
        BoxEditor(detections: [det(300, 20, 340, 280, "あ"), det(240, 20, 280, 280, "い"), det(180, 20, 220, 280, "う")],
                  imageSize: CGSize(width: 400, height: 300))
    }

    func testSetRectMarksChangedKeepsTextAndUndoes() {
        var e = makeEditor()
        e.setRect(1, CGRect(x: 250, y: 30, width: 40, height: 200))
        XCTAssertEqual(e.pendingCount, 1)
        XCTAssertEqual(e.detections[1].box, [250, 30, 290, 230])
        XCTAssertEqual(e.detections[1].text, "い")
        e.undo()
        XCTAssertEqual(e.detections[1].box, [240, 20, 280, 280])
        XCTAssertEqual(e.pendingCount, 0)
        XCTAssertFalse(e.canUndo)
    }

    func testSetRectIsClampedToImage() {
        var e = makeEditor()
        e.setRect(0, CGRect(x: 380, y: 20, width: 100, height: 100))
        XCTAssertEqual(e.detections[0].box, [380, 20, 400, 120])
    }

    func testDeleteAndUndo() {
        var e = makeEditor()
        e.selected = 1
        e.delete(1)
        XCTAssertEqual(e.detections.map(\.text), ["あ", "う"])
        XCTAssertNil(e.selected)
        XCTAssertEqual(e.pendingCount, 0)
        e.undo()
        XCTAssertEqual(e.detections.map(\.text), ["あ", "い", "う"])
    }

    func testAddSelectsNewBoxAndRejectsTinyOnes() {
        var e = makeEditor()
        XCTAssertNil(e.add(CGRect(x: 10, y: 10, width: 5, height: 5)))
        XCTAssertEqual(e.items.count, 3)
        XCTAssertEqual(e.add(CGRect(x: 10, y: 10, width: 40, height: 200)), 3)
        XCTAssertEqual(e.selected, 3)
        XCTAssertEqual(e.pending.map(\.index), [3])
        XCTAssertEqual(e.detections[3].text, "")
    }

    func testSplitProducesTwoPiecesBothPending() {
        var e = makeEditor()
        XCTAssertTrue(e.split(0, at: CGPoint(x: 320, y: 100)))
        XCTAssertEqual(e.items.count, 4)
        XCTAssertEqual(e.detections[0].box, [300, 20, 340, 100])
        XCTAssertEqual(e.detections[1].box, [300, 100, 340, 280])
        XCTAssertEqual(e.pendingCount, 2)
        XCTAssertFalse(e.split(0, at: CGPoint(x: 0, y: 0)))
        e.undo()
        XCTAssertEqual(e.items.count, 3)
    }

    func testMergeBecomesUnionAndClearsText() {
        var e = makeEditor()
        XCTAssertEqual(e.merge(2, 1), 1)
        XCTAssertEqual(e.items.count, 2)
        XCTAssertEqual(e.detections[1].box, [180, 20, 280, 280])
        XCTAssertEqual(e.detections[1].text, "")
        XCTAssertNil(e.merge(0, 0))
    }

    func testUndoStackWalksBackThroughSeveralEdits() {
        var e = makeEditor()
        e.delete(0)
        e.add(CGRect(x: 10, y: 10, width: 40, height: 100))
        e.merge(0, 1)
        e.undo(); e.undo(); e.undo()
        XCTAssertEqual(e.detections.map(\.text), ["あ", "い", "う"])
        XCTAssertFalse(e.canUndo)
    }

    func testApplyingRecognitionFillsOnlyPendingLines() {
        var e = makeEditor()
        e.setRect(2, CGRect(x: 170, y: 20, width: 50, height: 260))
        let read = [det(170, 20, 220, 280, "ウ")]
        let full = e.detections(applying: read)
        XCTAssertEqual(full.map(\.text), ["あ", "い", "ウ"])
        e.commitRecognition(full)
        XCTAssertEqual(e.pendingCount, 0)
        e.undo()
        XCTAssertEqual(e.detections.map(\.text), ["あ", "い", "う"])
        XCTAssertEqual(e.pendingCount, 1)
    }

    func testModeIsInferredFromClassNames() {
        XCTAssertEqual(makeEditor().inferredMode, .koten)
        let ndl = BoxEditor(detections: [Detection(box: [0, 0, 50, 20], score: 1, classId: 1, className: "line_main")],
                            imageSize: CGSize(width: 100, height: 100))
        XCTAssertEqual(ndl.inferredMode, .ndl)
    }
}
