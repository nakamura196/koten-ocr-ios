import XCTest
import OnnxRuntimeBindings
@testable import KotenOCR

/// Performance comparison: sequential vs parallel OCR recognition
final class OCRPerformanceTests: XCTestCase {

    private var env: ORTEnv!
    private var kotenDetector: RTMDetector!
    private var kotenRecognizer: PARSEQRecognizer!
    private var ndlDetector: DEIMDetector!
    private var cascadeRecognizer: CascadePARSEQRecognizer!

    override func setUpWithError() throws {
        env = try ORTEnv(loggingLevel: .warning)

        guard let charPath = Bundle.main.path(forResource: "NDLmoji", ofType: "yaml", inDirectory: "Models") else {
            throw XCTSkip("Models not available")
        }

        // Koten models
        if let detPath = Bundle.main.path(forResource: "rtmdet-s-1280x1280", ofType: "onnx", inDirectory: "Models"),
           let recPath = Bundle.main.path(forResource: "parseq-ndl-32x384-tiny-10", ofType: "onnx", inDirectory: "Models") {
            kotenDetector = try RTMDetector(env: env, modelPath: detPath)
            kotenRecognizer = try PARSEQRecognizer(env: env, modelPath: recPath, charListPath: charPath)
        }

        // NDL models
        if let deimPath = Bundle.main.path(forResource: "deim-s-1024x1024", ofType: "onnx", inDirectory: "Models"),
           let configPath = Bundle.main.path(forResource: "ndl-deim", ofType: "yaml", inDirectory: "Models"),
           let rec30Path = Bundle.main.path(forResource: "parseq-ndl-16x256-30-tiny-192epoch-tegaki3", ofType: "onnx", inDirectory: "Models"),
           let rec50Path = Bundle.main.path(forResource: "parseq-ndl-16x384-50-tiny-146epoch-tegaki2", ofType: "onnx", inDirectory: "Models"),
           let rec100Path = Bundle.main.path(forResource: "parseq-ndl-16x768-100-tiny-165epoch-tegaki2", ofType: "onnx", inDirectory: "Models") {
            ndlDetector = try DEIMDetector(env: env, modelPath: deimPath, configPath: configPath)
            let r30 = try PARSEQRecognizer(env: env, modelPath: rec30Path, charListPath: charPath, inputWidth: 256, inputHeight: 16)
            let r50 = try PARSEQRecognizer(env: env, modelPath: rec50Path, charListPath: charPath, inputWidth: 384, inputHeight: 16)
            let r100 = try PARSEQRecognizer(env: env, modelPath: rec100Path, charListPath: charPath, inputWidth: 768, inputHeight: 16)
            cascadeRecognizer = CascadePARSEQRecognizer(recognizer30: r30, recognizer50: r50, recognizer100: r100)
        }
    }

    private func loadImage(path: String) -> CGImage? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            return nil
        }
        return image
    }

    // MARK: - Koten benchmark (classical text)

    func testKotenBenchmark() async throws {
        guard let detector = kotenDetector, let recognizer = kotenRecognizer else {
            throw XCTSkip("Koten models not loaded")
        }
        guard let image = loadImage(path: "/tmp/koten_test.jpg") else {
            throw XCTSkip("Koten test image not found")
        }
        print("Image: koten_test.jpg (\(image.width)x\(image.height))")

        // Detection
        let detStart = CFAbsoluteTimeGetCurrent()
        let detections = try detector.detect(image: image)
        let detTime = CFAbsoluteTimeGetCurrent() - detStart
        print("Detection: \(String(format: "%.3f", detTime))s → \(detections.count) regions")

        // Sequential recognition
        let seqStart = CFAbsoluteTimeGetCurrent()
        for det in detections {
            let rect = CGRect(x: max(0, det.box[0]), y: max(0, det.box[1]),
                              width: max(1, det.box[2] - det.box[0]),
                              height: max(1, det.box[3] - det.box[1]))
            if let cropped = image.cropping(to: rect) {
                _ = try recognizer.recognize(image: cropped)
            }
        }
        let seqTime = CFAbsoluteTimeGetCurrent() - seqStart

        // Parallel recognition
        let parStart = CFAbsoluteTimeGetCurrent()
        _ = try await withThrowingTaskGroup(of: String.self) { group in
            for det in detections {
                let rect = CGRect(x: max(0, det.box[0]), y: max(0, det.box[1]),
                                  width: max(1, det.box[2] - det.box[0]),
                                  height: max(1, det.box[3] - det.box[1]))
                guard let cropped = image.cropping(to: rect) else { continue }
                group.addTask { try recognizer.recognize(image: cropped) }
            }
            var results: [String] = []
            for try await r in group { results.append(r) }
            return results
        }
        let parTime = CFAbsoluteTimeGetCurrent() - parStart

        // Batched parallel (max 4 concurrent)
        let batchStart = CFAbsoluteTimeGetCurrent()
        let maxConcurrency = 4
        var batchResults2: [String] = []
        for chunkStart in stride(from: 0, to: detections.count, by: maxConcurrency) {
            let chunkEnd = min(chunkStart + maxConcurrency, detections.count)
            let chunk = try await withThrowingTaskGroup(of: String.self) { group in
                for i in chunkStart..<chunkEnd {
                    let det = detections[i]
                    let rect = CGRect(x: max(0, det.box[0]), y: max(0, det.box[1]),
                                      width: max(1, det.box[2] - det.box[0]),
                                      height: max(1, det.box[3] - det.box[1]))
                    guard let cropped = image.cropping(to: rect) else { continue }
                    group.addTask { try recognizer.recognize(image: cropped) }
                }
                var r: [String] = []
                for try await s in group { r.append(s) }
                return r
            }
            batchResults2.append(contentsOf: chunk)
        }
        let batchTime = CFAbsoluteTimeGetCurrent() - batchStart

        let kotenSpeedup = seqTime / parTime
        let kotenBatchSpeedup = seqTime / batchTime
        print("")
        print("=== Koten OCR Results ===")
        print("Regions:      \(detections.count)")
        print("Sequential:   \(String(format: "%.3f", seqTime))s")
        print("Unlimited:    \(String(format: "%.3f", parTime))s (\(String(format: "%.2f", kotenSpeedup))x)")
        print("Batched (4):  \(String(format: "%.3f", batchTime))s (\(String(format: "%.2f", kotenBatchSpeedup))x)")
    }

    // MARK: - NDL benchmark (modern printed text)

    func testNDLBenchmark() async throws {
        guard let detector = ndlDetector, let cascade = cascadeRecognizer else {
            throw XCTSkip("NDL models not loaded")
        }
        guard let image = loadImage(path: "/tmp/ndl_modern_test.jpg") else {
            throw XCTSkip("NDL test image not found")
        }
        print("Image: ndl_modern_test.jpg (\(image.width)x\(image.height))")

        // Detection
        let detStart = CFAbsoluteTimeGetCurrent()
        let detections = try detector.detect(image: image)
        let detTime = CFAbsoluteTimeGetCurrent() - detStart
        print("Detection: \(String(format: "%.3f", detTime))s → \(detections.count) regions")

        // Sequential recognition
        let seqStart = CFAbsoluteTimeGetCurrent()
        for det in detections {
            let rect = CGRect(x: max(0, det.box[0]), y: max(0, det.box[1]),
                              width: max(1, det.box[2] - det.box[0]),
                              height: max(1, det.box[3] - det.box[1]))
            if let cropped = image.cropping(to: rect) {
                _ = try cascade.recognize(image: cropped, predCharCount: det.predCharCount)
            }
        }
        let seqTime = CFAbsoluteTimeGetCurrent() - seqStart

        // Parallel recognition
        let parStart = CFAbsoluteTimeGetCurrent()
        _ = try await withThrowingTaskGroup(of: String.self) { group in
            for det in detections {
                let rect = CGRect(x: max(0, det.box[0]), y: max(0, det.box[1]),
                                  width: max(1, det.box[2] - det.box[0]),
                                  height: max(1, det.box[3] - det.box[1]))
                guard let cropped = image.cropping(to: rect) else { continue }
                let charCount = det.predCharCount
                group.addTask { try cascade.recognize(image: cropped, predCharCount: charCount) }
            }
            var results: [String] = []
            for try await r in group { results.append(r) }
            return results
        }
        let parTime = CFAbsoluteTimeGetCurrent() - parStart

        // Batched parallel (max 4 concurrent)
        let ndlMaxConcurrency = 4
        let batchStart2 = CFAbsoluteTimeGetCurrent()
        for chunkStart in stride(from: 0, to: detections.count, by: ndlMaxConcurrency) {
            let chunkEnd = min(chunkStart + ndlMaxConcurrency, detections.count)
            _ = try await withThrowingTaskGroup(of: String.self) { group in
                for i in chunkStart..<chunkEnd {
                    let det = detections[i]
                    let rect = CGRect(x: max(0, det.box[0]), y: max(0, det.box[1]),
                                      width: max(1, det.box[2] - det.box[0]),
                                      height: max(1, det.box[3] - det.box[1]))
                    guard let cropped = image.cropping(to: rect) else { continue }
                    let charCount = det.predCharCount
                    group.addTask { try cascade.recognize(image: cropped, predCharCount: charCount) }
                }
                var r: [String] = []
                for try await s in group { r.append(s) }
                return r
            }
        }
        let batchTime = CFAbsoluteTimeGetCurrent() - batchStart2

        let speedup = seqTime / parTime
        let batchSpeedup = seqTime / batchTime
        print("")
        print("=== NDL OCR Results ===")
        print("Regions:      \(detections.count)")
        print("Sequential:   \(String(format: "%.3f", seqTime))s")
        print("Unlimited:    \(String(format: "%.3f", parTime))s (\(String(format: "%.2f", speedup))x)")
        print("Batched (4):  \(String(format: "%.3f", batchTime))s (\(String(format: "%.2f", batchSpeedup))x)")
    }
}
