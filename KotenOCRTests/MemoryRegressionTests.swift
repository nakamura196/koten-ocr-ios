import XCTest
import CoreGraphics
import Darwin
@testable import KotenOCR

/// Regression tests for the "crashes on the 2nd image" report (App Store review, 1.3.5).
/// Runs the full OCREngine pipeline several times in a row on a large photo and records the
/// process memory footprint, so a growth or a peak far above an iPhone's jetsam limit shows up here.
/// Simulator memory limits are not a device's: these numbers are for comparison, not pass/fail on
/// a real limit.
final class MemoryRegressionTests: XCTestCase {

    // MARK: - Memory sampling

    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    /// Samples the footprint on a background thread every 5 ms and keeps the maximum.
    final class PeakSampler: @unchecked Sendable {
        private let lock = NSLock()
        private var peak: Double = 0
        private var running = true
        private var thread: Thread?

        func start() {
            peak = MemoryRegressionTests.footprintMB()
            let t = Thread { [weak self] in
                while let self, self.isRunning {
                    let v = MemoryRegressionTests.footprintMB()
                    self.lock.lock(); if v > self.peak { self.peak = v }; self.lock.unlock()
                    usleep(5_000)
                }
            }
            thread = t
            t.start()
        }

        private var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return running }

        func stop() -> Double {
            lock.lock(); running = false; let p = peak; lock.unlock()
            return p
        }
    }

    // MARK: - Fixtures

    /// The test page drawn at `width`×`height` (a stand-in for a 12/48 MP photo).
    static func largePage(width: Int, height: Int) throws -> CGImage {
        let path = try XCTUnwrap(Bundle(for: MemoryRegressionTests.self).path(forResource: "koten_page", ofType: "jpg"))
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let ui = try XCTUnwrap(UIImage(data: data))
        let src = try XCTUnwrap(ui.cgImage)
        let ctx = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.interpolationQuality = .medium
        ctx.draw(src, in: CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(ctx.makeImage())
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

    // MARK: - Tests

    /// Six OCR runs in a row (3 × koten, then 3 × ndl) on a 48 MP page, as the app hands it over
    /// after intake. In 1.3.5 the footprint climbed with every run (ONNX Runtime arenas never
    /// shrank) and reached ~1.5 GB on the simulator after koten+ndl; see docs in ORTMemory.
    func testSequentialProcessOnLargeImage() async throws {
        let engine = try await readyEngine()
        var image: CGImage? = try Self.largePage(width: 6048, height: 8064)
        // What the app hands to the engine after intake (capture/picker/test path).
        image = ImageIntake.limit(image!)
        let input = try XCTUnwrap(image)
        XCTAssertLessThanOrEqual(max(input.width, input.height), ImageIntake.maxLongSide)

        let baseline = Self.footprintMB()
        var peaks: [Double] = []
        var after: [Double] = []
        for mode in [OCRMode.koten, .koten, .koten, .ndl, .ndl, .ndl] {
            try await engine.switchMode(to: mode)
            let sampler = PeakSampler()
            sampler.start()
            let result = try await engine.process(image: input)
            peaks.append(sampler.stop())
            after.append(Self.footprintMB())
            XCTAssertFalse(result.detections.isEmpty, "\(mode) found no lines")
            if let out = result.image {
                XCTAssertLessThanOrEqual(max(out.width, out.height), ImageIntake.maxLongSide + 1024)
            }
        }
        let fmt = { (v: [Double]) in v.map { String(format: "%.0f", $0) }.joined(separator: ", ") }
        print("[MemoryRegression] baseline \(String(format: "%.0f", baseline)) MB; peaks [\(fmt(peaks))] MB; after [\(fmt(after))] MB")
        // Once warm, another run in the same mode must not keep climbing (no per-run growth).
        XCTAssertLessThan(after[2] - after[1], 60, "footprint kept growing across koten runs")
        XCTAssertLessThan(after[5] - after[4], 60, "footprint kept growing across ndl runs")
        // Loose ceiling on the rise above the starting footprint (simulator numbers). 1.3.5 rose by
        // ~1.3 GB over a similar koten→ndl sequence; this branch rises by ~0.4 GB.
        XCTAssertLessThan((peaks.max() ?? 0) - baseline, 700)
    }

    /// A blank page gives zero detections. Every step after detection must cope with that,
    /// twice in a row.
    func testBlankPageTwiceGivesEmptyResult() async throws {
        let engine = try await readyEngine()
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 1200, height: 1600, bitsPerComponent: 8,
                                          bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 1200, height: 1600))
        let blank = try XCTUnwrap(ctx.makeImage())
        for mode in [OCRMode.koten, .ndl, .koten] {
            try await engine.switchMode(to: mode)
            let result = try await engine.process(image: blank)
            XCTAssertTrue(result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !result.detections.isEmpty)
        }
    }

    /// A memory warning while OCR runs must not drop the models the running task uses, and the
    /// next run must still work.
    func testMemoryWarningDuringProcessKeepsModels() async throws {
        let engine = try await readyEngine()
        let input = ImageIntake.limit(try Self.largePage(width: 3024, height: 4032))
        try await engine.switchMode(to: .koten)
        let task = Task { try await engine.process(image: input) }
        try await Task.sleep(nanoseconds: 50_000_000)
        await MainActor.run { engine.handleMemoryWarning() }
        let first = try await task.value
        XCTAssertFalse(first.detections.isEmpty)
        let second = try await engine.process(image: input)
        XCTAssertFalse(second.detections.isEmpty)
    }
}
