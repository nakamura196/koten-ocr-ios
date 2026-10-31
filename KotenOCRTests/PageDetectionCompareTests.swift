import XCTest
import CoreGraphics
import ImageIO
@testable import KotenOCR

/// Compares the two Vision page detectors. Extra local images (not in the repository) can be passed
/// as PAGEDET_EXTRA (set TEST_RUNNER_PAGEDET_EXTRA for xcodebuild); they are skipped when missing.
final class PageDetectionCompareTests: XCTestCase {

    private func load(_ path: String) throws -> CGImage {
        guard FileManager.default.fileExists(atPath: path) else { throw XCTSkip("missing \(path)") }
        let url = URL(fileURLWithPath: path)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { throw XCTSkip("unreadable") }
        return img
    }

    private func report(_ name: String, _ img: CGImage) {
        for (label, m) in [("rect", PerspectiveCrop.DetectionMethod.rectangles), ("doc", .documentSegmentation)] {
            if let r = PerspectiveCrop.detectPageWithConfidence(in: img, method: m, minimumConfidence: 0.0) {
                let pts = r.quad.points.map { String(format: "(%.3f,%.3f)", $0.x, $0.y) }.joined(separator: " ")
                print("PAGEDET \(name) \(label) conf=\(r.confidence) full=\(PerspectiveCrop.isNearlyFullFrame(r.quad)) convex=\(r.quad.isConvex) \(pts)")
            } else {
                print("PAGEDET \(name) \(label) none")
            }
        }
    }

    func testCompareOnLocalImages() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        var any = false
        let extra = ProcessInfo.processInfo.environment["PAGEDET_EXTRA"].map { [("extra", $0)] } ?? []
        for (name, path) in extra + [
            ("shibata", repo.appendingPathComponent("KotenOCR/Resources/sample_shibata.jpg").path),
            ("koten_sample", repo.appendingPathComponent("KotenOCRUITests/Resources/test_koten_sample.jpg").path),
            ("ndl_sample", repo.appendingPathComponent("KotenOCRUITests/Resources/test_ndl_sample.jpg").path),
        ] {
            guard let img = try? load(path) else { continue }
            any = true
            report(name, img)
        }
        if !any { throw XCTSkip("no images") }
    }

    func testUsableDetection() {
        XCTAssertFalse(PerspectiveCrop.isUsableDetection(.unit))
        XCTAssertFalse(PerspectiveCrop.isUsableDetection(Quad(rect: CGRect(x: 0.01, y: 0.01, width: 0.98, height: 0.98))))
        XCTAssertTrue(PerspectiveCrop.isUsableDetection(Quad(rect: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8))))
        let tilted = Quad(topLeft: CGPoint(x: 0.1, y: 0.15), topRight: CGPoint(x: 0.9, y: 0.05),
                          bottomRight: CGPoint(x: 0.95, y: 0.9), bottomLeft: CGPoint(x: 0.05, y: 0.8))
        XCTAssertTrue(PerspectiveCrop.isUsableDetection(tilted))
        let bowtie = Quad(topLeft: CGPoint(x: 0.1, y: 0.1), topRight: CGPoint(x: 0.9, y: 0.9),
                          bottomRight: CGPoint(x: 0.9, y: 0.1), bottomLeft: CGPoint(x: 0.1, y: 0.9))
        XCTAssertFalse(PerspectiveCrop.isUsableDetection(bowtie))
    }
}
