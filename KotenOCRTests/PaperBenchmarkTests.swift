import XCTest
import CoreGraphics
@testable import KotenOCR

/// Timing and memory for the paper (§6.1, §6.3). Meant to run on a device; numbers are printed with a
/// [Bench] prefix. Skipped unless BENCH=1 is set, so the regular suite stays fast.
final class PaperBenchmarkTests: XCTestCase {

    private func skipUnlessRequested() throws {
        if ProcessInfo.processInfo.environment["BENCH"] != "1" { throw XCTSkip("set BENCH=1 to run") }
    }

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

    private func sample(_ name: String) throws -> CGImage {
        let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "jpg"))
        return try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage)
    }

    /// A real high-resolution page: NDL 源氏物語 (pid 2585098), frame 5, right half, 3254×3800, public domain.
    /// Replaces the synthetic 12 MP page drawn by MemoryRegressionTests.largePage.
    private func realPage() throws -> CGImage {
        let path = try XCTUnwrap(Bundle(for: Self.self).path(forResource: "genji_ndl_2585098_R0005_right", ofType: "jpg"))
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try XCTUnwrap(UIImage(data: data)?.cgImage)
    }

    /// Device state, so a slow run can be told apart from thermal throttling or Low Power Mode.
    private func deviceState() -> String {
        let p = ProcessInfo.processInfo
        let t = ["nominal", "fair", "serious", "critical"][min(p.thermalState.rawValue, 3)]
        return "thermal \(t) | lowPower \(p.isLowPowerModeEnabled)"
    }

    private func median(_ v: [Double]) -> Double {
        let s = v.sorted(); return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    /// Median time and peak footprint per page: 1 warm-up, then 5 timed runs per condition.
    func testTimeAndMemoryPerPage() async throws {
        try skipUnlessRequested()
        let engine = try await readyEngine()
        print("[Bench] state at start: \(deviceState())")
        let photo = ImageIntake.limit(try realPage())
        let cases: [(String, OCRMode, CGImage, Bool)] = [
            ("koten genji sample, correction off", .koten, try sample("sample_genji"), false),
            ("koten genji sample, correction on", .koten, try sample("sample_genji"), true),
            ("koten real hi-res page, correction off", .koten, photo, false),
            ("koten real hi-res page, correction on", .koten, photo, true),
            ("ndl modern sample", .ndl, try sample("sample_modern"), true),
        ]
        let key = Deskew.settingsKey
        defer { UserDefaults.standard.removeObject(forKey: key) }
        for (label, mode, image, correction) in cases {
            UserDefaults.standard.set(correction, forKey: key)
            try await engine.switchMode(to: mode)
            _ = try await engine.process(image: image)
            var times: [Double] = []; var peak = 0.0; var lines = 0
            for _ in 0..<5 {
                let sampler = MemoryRegressionTests.PeakSampler(); sampler.start()
                let t0 = CFAbsoluteTimeGetCurrent()
                let r = try await engine.process(image: image)
                times.append(CFAbsoluteTimeGetCurrent() - t0)
                peak = max(peak, sampler.stop()); lines = r.detections.count
            }
            print("[Bench] state after \(label): \(deviceState())")
            print(String(format: "[Bench] %@ | %dx%d | lines %d | median %.2f s (min %.2f max %.2f) | peak %.0f MB",
                         label, image.width, image.height, lines, median(times), times.min()!, times.max()!, peak))
        }
    }

    /// Repeated capture: 30 pages in a row on the real hi-res page, alternating Classical and Modern.
    func testRepeatedPages() async throws {
        try skipUnlessRequested()
        let engine = try await readyEngine()
        let photo = ImageIntake.limit(try realPage())
        let baseline = MemoryRegressionTests.footprintMB()
        var peaks: [Double] = []; var after: [Double] = []
        for i in 0..<30 {
            try await engine.switchMode(to: i % 2 == 0 ? .koten : .ndl)
            let sampler = MemoryRegressionTests.PeakSampler(); sampler.start()
            let r = try await engine.process(image: photo)
            peaks.append(sampler.stop()); after.append(MemoryRegressionTests.footprintMB())
            XCTAssertFalse(r.detections.isEmpty)
        }
        let fmt = { (v: [Double]) in v.map { String(format: "%.0f", $0) }.joined(separator: ",") }
        print("[Bench] state after repeated 30: \(deviceState())")
        print("[Bench] repeated 30 | baseline \(String(format: "%.0f", baseline)) MB | max peak \(String(format: "%.0f", peaks.max()!)) MB")
        print("[Bench] peaks [\(fmt(peaks))]")
        print("[Bench] after [\(fmt(after))]")
    }
}
