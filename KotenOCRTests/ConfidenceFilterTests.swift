import XCTest
@testable import KotenOCR

final class ConfidenceFilterTests: XCTestCase {

    private func det(_ score: Float, _ text: String, cls: String = "text") -> Detection {
        Detection(box: [0, 0, 10, 100], score: score, classId: 0, className: cls, text: text)
    }

    private var lines: [Detection] {
        [det(0.9, "一"), det(0.35, "二"), det(0.5, "三"), det(0.28, "四")]
    }

    func testHidesOnlyLinesBelowTheThreshold() {
        let v = ConfidenceFilter.visible(lines, threshold: 0.5)
        XCTAssertEqual(v.map(\.index), [0, 2], "0.5 itself stays")
        XCTAssertEqual(ConfidenceFilter.visible(lines, threshold: 0.3).map(\.index), [0, 1, 2])
    }

    func testTextFollowsTheFilterAndSkipsEmptyLines() {
        let l = lines + [det(0.95, "")]
        XCTAssertEqual(ConfidenceFilter.text(l, threshold: 0.5), "一\n三")
        XCTAssertEqual(ConfidenceFilter.text(l, threshold: 0.25), "一\n二\n三\n四")
    }

    func testFilterDoesNotChangeTheStoredLines() {
        let l = lines
        _ = ConfidenceFilter.visible(l, threshold: 0.9)
        XCTAssertEqual(l.count, 4)
        XCTAssertEqual(l[3].score, 0.28)
    }

    func testInitialValueIsThePointThree() {
        XCTAssertEqual(ConfidenceFilter.defaultThreshold, 0.3)
        XCTAssertEqual(ConfidenceFilter.visible([det(0.3, "x", cls: "line_main")], threshold: ConfidenceFilter.defaultThreshold).count, 1)
    }

    func testPercentText() {
        XCTAssertEqual(ConfidenceFilter.percentText(0.3), "30%")
        XCTAssertEqual(ConfidenceFilter.percentText(0.55), "55%")
    }

    func testReaderEditedLinesAreNeverHidden() {
        var d = det(0.1, "x")
        d.markReaderConfirmed()
        XCTAssertEqual(ConfidenceFilter.visible([d], threshold: ConfidenceFilter.range.upperBound).count, 1)

        var editor = BoxEditor(detections: [det(0.3, "a"), det(0.3, "b")], imageSize: CGSize(width: 200, height: 200))
        editor.setRect(0, CGRect(x: 5, y: 5, width: 20, height: 100))
        XCTAssertEqual(editor.detections[0].score, 1.0, "moved box is the reader's")
        XCTAssertEqual(editor.detections[1].score, 0.3, "untouched box keeps its score")
        let added = editor.add(CGRect(x: 50, y: 50, width: 30, height: 60))
        XCTAssertEqual(editor.detections[added!].score, 1.0)
    }
}
