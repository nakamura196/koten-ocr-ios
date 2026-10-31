import XCTest
import CoreGraphics
import UIKit
@testable import KotenOCR

/// Reads the eval/tilt images with the app's own koten pipeline (gated deskew, per-line oriented crops,
/// duplicate-line removal; the app's defaults) and writes one JSON line per image for eval/tilt/score_jsonl.py.
/// Meant for the simulator, which can read and write host paths. Skipped unless EVAL_MANIFEST is set
/// (pass it as TEST_RUNNER_EVAL_MANIFEST to xcodebuild); EVAL_OUT is the JSONL to write.
final class EvalTiltTests: XCTestCase {

    private func readyEngine() async throws -> OCREngine {
        let engine = OCREngine()
        engine.currentModeRaw = OCRMode.koten.rawValue
        engine.initialize()
        for _ in 0..<600 {
            if engine.state == .ready { return engine }
            if case .error(let msg) = engine.state { throw XCTSkip("Models not available: \(msg)") }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw XCTSkip("Engine did not become ready")
    }

    private func record(_ engine: OCREngine, file: String, image: CGImage) async throws -> [String: Any] {
        let t0 = CFAbsoluteTimeGetCurrent()
        let r = try await engine.process(image: image)
        let secs = CFAbsoluteTimeGetCurrent() - t0
        let lines: [[String: Any]] = r.detections.map { ["box": $0.box, "score": Double($0.score), "text": $0.text] }
        return ["image_file": file, "width": image.width, "height": image.height,
                "secs": (secs * 100).rounded() / 100, "lines": lines]
    }

    func testReadManifest() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let manifest = env["EVAL_MANIFEST"], let out = env["EVAL_OUT"] else { throw XCTSkip("set EVAL_MANIFEST and EVAL_OUT") }
        UserDefaults.standard.removeObject(forKey: Deskew.settingsKey)   // app default: on
        let root = (manifest as NSString).deletingLastPathComponent
        // image_file is the first column and never quoted; the other columns are not needed here.
        let files = try String(contentsOfFile: manifest, encoding: .utf8)
            .split(whereSeparator: \.isNewline).dropFirst()   // Python's csv writes CRLF, one Character in Swift
            .compactMap { $0.split(separator: ",", maxSplits: 1).first.map(String.init) }
        let engine = try await readyEngine()
        FileManager.default.createFile(atPath: out, contents: nil)
        let handle = try XCTUnwrap(FileHandle(forWritingAtPath: out))
        defer { try? handle.close() }
        for (k, file) in files.enumerated() {
            let ui = try XCTUnwrap(UIImage(contentsOfFile: (root as NSString).appendingPathComponent(file)), file)
            let image = try XCTUnwrap(ImageIntake.limit(ui), file)   // as when a photo is imported
            let row = try await record(engine, file: file, image: image)
            var data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
            data.append(0x0A)
            try handle.write(contentsOf: data)
            if (k + 1) % 50 == 0 { print("[Eval] \(k + 1)/\(files.count)") }
        }
        print("[Eval] wrote \(files.count) rows to \(out)")
    }

    /// The Shibata photo (bundled as a sample) read as in the app.
    func testShibataSample() async throws {
        guard ProcessInfo.processInfo.environment["EVAL_MANIFEST"] != nil else { throw XCTSkip("set EVAL_MANIFEST") }
        UserDefaults.standard.removeObject(forKey: Deskew.settingsKey)
        let engine = try await readyEngine()
        let url = try XCTUnwrap(Bundle.main.url(forResource: "sample_shibata", withExtension: "jpg"))
        let image = try XCTUnwrap(ImageIntake.limit(try XCTUnwrap(UIImage(contentsOfFile: url.path))))
        let r = try await engine.process(image: image)
        print("[Eval] shibata \(image.width)x\(image.height) lines \(r.detections.count)")
        for d in r.detections { print("[Eval] shibata line \(d.box) \(d.text)") }
    }
}
