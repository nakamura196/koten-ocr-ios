import XCTest
@testable import KotenOCR

/// Re-reading hand-corrected boxes with the real models and the bundled koten sample.
final class BoxEditRereadTests: XCTestCase {

    private var resources: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("KotenOCRUITests/Resources")
    }

    private func loadImage(_ name: String) throws -> CGImage {
        let data = try Data(contentsOf: resources.appendingPathComponent(name))
        let image = try XCTUnwrap(UIImage(data: data)?.normalizedCGImage)
        return image
    }

    @MainActor
    private func readyEngine(mode: OCRMode) async throws -> OCREngine {
        // The yaml files are in git; the onnx models are not (CI has none).
        guard Bundle.main.path(forResource: "rtmdet-s-1280x1280", ofType: "onnx", inDirectory: "Models") != nil,
              Bundle.main.path(forResource: "deim-s-1024x1024", ofType: "onnx", inDirectory: "Models") != nil else {
            throw XCTSkip("Models not available")
        }
        let engine = OCREngine()
        engine.currentModeRaw = OCRMode.koten.rawValue
        engine.initialize()
        for _ in 0..<600 where !engine.state.isReady {
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        XCTAssertTrue(engine.state.isReady)
        if mode == .ndl { try await engine.switchMode(to: .ndl) }
        return engine
    }

    private func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        for i in 1...a.count {
            var cur = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[b.count]
    }

    @MainActor
    func testDeleteThenDrawBoxOverOneColumnReadsTheSameText() async throws {
        let engine = try await readyEngine(mode: .koten)
        let image = try loadImage("test_koten_sample.jpg")
        let result = try await engine.process(image: image)
        // The longest line is the most reliable one to compare.
        let target = try XCTUnwrap(result.detections.max { $0.text.count < $1.text.count })
        XCTAssertGreaterThanOrEqual(target.text.count, 3)
        let targetIndex = try XCTUnwrap(result.detections.firstIndex { $0.box == target.box })

        var editor = BoxEditor(detections: result.detections, imageSize: CGSize(width: image.width, height: image.height))
        editor.delete(targetIndex)
        XCTAssertEqual(editor.items.count, result.detections.count - 1)
        // Draw a box that covers the same column, slightly off from the detector's box.
        let drawn = target.rect.insetBy(dx: -3, dy: 4)
        XCTAssertNotNil(editor.add(drawn))
        XCTAssertEqual(editor.pendingCount, 1)

        let recognized = try await engine.recognize(boxes: editor.pending.map(\.detection), in: image,
                                                    mode: editor.inferredMode ?? .koten)
        XCTAssertEqual(recognized.count, 1)
        let text = recognized[0].text
        XCTAssertFalse(text.isEmpty)
        let distance = levenshtein(text, target.text)
        XCTAssertLessThanOrEqual(distance, max(2, target.text.count / 3),
                                 "re-read \"\(text)\" vs original \"\(target.text)\"")

        let ordered = engine.orderReading(editor.detections(applying: recognized),
                                          imageWidth: image.width, imageHeight: image.height)
        editor.commitRecognition(ordered)
        XCTAssertEqual(editor.items.count, result.detections.count)
        XCTAssertEqual(editor.pendingCount, 0)
        XCTAssertTrue(editor.detections.allSatisfy { !$0.text.isEmpty })
    }

    @MainActor
    func testRereadWorksInNDLModeWithTheCascadeRecognizer() async throws {
        let engine = try await readyEngine(mode: .ndl)
        let image = try loadImage("test_ndl_sample.jpg")
        let result = try await engine.process(image: image)
        let target = try XCTUnwrap(result.detections.max { $0.text.count < $1.text.count })
        var box = target
        box.text = ""
        let recognized = try await engine.recognize(boxes: [box], in: image, mode: .ndl)
        XCTAssertFalse(recognized[0].text.isEmpty)
        XCTAssertLessThanOrEqual(levenshtein(recognized[0].text, target.text), max(2, target.text.count / 3))
    }

    @MainActor
    func testEmptyInputAndOutOfImageBoxes() async throws {
        let engine = try await readyEngine(mode: .koten)
        let image = try loadImage("test_koten_sample.jpg")
        let none = try await engine.recognize(boxes: [], in: image, mode: .koten)
        XCTAssertTrue(none.isEmpty)
        // A box far outside the image must not crash; it just yields no text.
        let outside = Detection(box: [image.width + 50, 0, image.width + 90, 100], score: 1, classId: 0, className: "text")
        let r = try await engine.recognize(boxes: [outside], in: image, mode: .koten)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].text, "")
    }
}
