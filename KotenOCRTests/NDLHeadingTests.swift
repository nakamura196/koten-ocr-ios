import XCTest
@testable import KotenOCR

/// Modern (NDL) mode must keep one-line headings and captions.
/// They used to be dropped because NMS let the surrounding text_block / block_* box win.
final class NDLHeadingTests: XCTestCase {

    private func det(_ className: String, _ box: [Int], _ score: Float) -> Detection {
        Detection(box: box, score: score, classId: 0, className: className)
    }

    func testLineInsideItsOwnBlockIsKept() {
        let block = det("text_block", [100, 100, 400, 130], 0.9)
        let title = det("line_title", [102, 102, 398, 128], 0.6)
        let kept = DEIMDetector.applyNMS([block, title], iouThreshold: 0.2)
        XCTAssertTrue(kept.contains { $0.className == "line_title" })
        XCTAssertEqual(kept.count, 2)
    }

    func testDuplicateLinesAreStillMerged() {
        let a = det("line_main", [100, 100, 400, 130], 0.9)
        let b = det("line_title", [101, 101, 399, 129], 0.5)
        let kept = DEIMDetector.applyNMS([a, b], iouThreshold: 0.2)
        XCTAssertEqual(kept.map(\.className), ["line_main"])
    }

    /// The bundled modern sample (NDL 2531162 frame 24, the image shipped with NDLOCR-Lite).
    /// The official NDLOCR-Lite result for this page (resource/digidepo_2531162_0024.xml) has 26 lines,
    /// including the headings "(ヱ)気送子送付管" and "(1)気送管" and the caption "(図2)送村官".
    @MainActor
    func testModernSampleKeepsHeadingsLikeTheOfficialResult() async throws {
        guard Bundle.main.path(forResource: "NDLmoji", ofType: "yaml", inDirectory: "Models") != nil else {
            throw XCTSkip("Models not available")
        }
        let url = try XCTUnwrap(Bundle.main.url(forResource: "sample_modern", withExtension: "jpg"))
        let image = try XCTUnwrap(UIImage(contentsOfFile: url.path)?.normalizedCGImage)

        let engine = OCREngine()
        engine.currentModeRaw = OCRMode.koten.rawValue
        engine.initialize()
        for _ in 0..<600 where !engine.state.isReady {
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        XCTAssertTrue(engine.state.isReady)
        try await engine.switchMode(to: .ndl)

        let result = try await engine.process(image: image)
        let lines = result.detections.map(\.text)
        print("NDL sample lines (\(lines.count)):\n" + lines.joined(separator: "\n"))

        XCTAssertGreaterThanOrEqual(lines.count, 25, "official NDLOCR-Lite finds 26 lines")
        XCTAssertTrue(result.detections.contains { $0.className == "line_title" }, "headings should survive")
        XCTAssertTrue(lines.contains { $0.contains("送付管") && !$0.contains("送付には") },
                      "heading (ヱ)気送子送付管 should be read")
        XCTAssertTrue(lines.contains { $0.contains("気送管") && $0.count <= 8 },
                      "heading (1)気送管 should be read")
    }
}
