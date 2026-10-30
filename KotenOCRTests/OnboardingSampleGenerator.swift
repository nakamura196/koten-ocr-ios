import XCTest
import UIKit
@testable import KotenOCR

/// Regenerates KotenOCR/Resources/onboarding_sample_ocr.json, the recognition result that the
/// first-run onboarding replays. It runs the app's real Koten pipeline (OCREngine, default
/// settings including auto-deskew) once on the onboarding sample page.
/// Steps: `python3 scripts/make_onboarding_sample.py`, then
///   TEST_RUNNER_ONBOARDING_SAMPLE_SOURCE=/tmp/onboarding_source.jpg \
///   TEST_RUNNER_ONBOARDING_SAMPLE_OUT=$PWD/KotenOCR/Resources/onboarding_sample_ocr.json \
///   xcodebuild test -scheme KotenOCR -destination 'platform=iOS Simulator,name=iPhone 17' \
///     -only-testing:KotenOCRTests/OnboardingSampleGenerator
/// Skipped unless ONBOARDING_SAMPLE_OUT is set. Without ONBOARDING_SAMPLE_SOURCE it reads the
/// bundled "OnboardingSample" asset. The output must not be edited by hand; if a line is visibly
/// wrong, choose a different crop instead.
@MainActor
final class OnboardingSampleGenerator: XCTestCase {

    func testGenerateOnboardingSample() async throws {
        let out = ProcessInfo.processInfo.environment["ONBOARDING_SAMPLE_OUT"] ?? ""
        try XCTSkipIf(out.isEmpty, "ONBOARDING_SAMPLE_OUT not set")
        // Optional full-resolution source of the same crop; the app ships a downscaled copy.
        // Boxes are normalized, so they fit both.
        let sourcePath = ProcessInfo.processInfo.environment["ONBOARDING_SAMPLE_SOURCE"] ?? ""
        let ui = sourcePath.isEmpty ? UIImage(named: "OnboardingSample") : UIImage(contentsOfFile: sourcePath)
        guard let ui, let image = ui.normalizedCGImage else {
            return XCTFail("OnboardingSample image missing")
        }

        let engine = OCREngine()
        engine.currentModeRaw = OCRMode.koten.rawValue
        engine.initialize()
        for _ in 0..<600 {
            if case .ready = engine.state { break }
            if case .error(let msg) = engine.state { return XCTFail(msg) }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        guard case .ready = engine.state else { return XCTFail("models did not load") }

        let result = try await engine.process(image: image)
        let processed = result.image ?? image
        let w = Double(processed.width), h = Double(processed.height)
        // Boxes are stored normalized (0...1) so the asset can be displayed at any size.
        let sample = OnboardingSample(
            source: "\(sourcePath.isEmpty ? "OnboardingSample asset" : (sourcePath as NSString).lastPathComponent), "
                + "\(processed.width)x\(processed.height); OCREngine Koten mode, default settings",
            rotated: processed.width != image.width || processed.height != image.height || result.image.map { $0 !== image } ?? false,
            lines: result.detections.map { d in
                OnboardingSample.Line(
                    box: [Double(d.box[0]) / w, Double(d.box[1]) / h, Double(d.box[2]) / w, Double(d.box[3]) / h],
                    text: d.text)
            })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(sample).write(to: URL(fileURLWithPath: out))
        print("onboarding sample: \(sample.lines.count) lines, rotated=\(sample.rotated)")
        sample.lines.forEach { print($0.text) }
    }
}
