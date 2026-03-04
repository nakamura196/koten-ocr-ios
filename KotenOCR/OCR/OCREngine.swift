import Foundation
import CoreGraphics
import OnnxRuntimeBindings

enum OCREngineState {
    case uninitialized
    case loading
    case ready
    case error(String)
}

struct OCRResult {
    let detections: [Detection]
    let text: String
}

class OCREngine: ObservableObject {
    @Published var state: OCREngineState = .uninitialized
    @Published var progress: Float = 0

    private var env: ORTEnv?
    private var detector: RTMDetector?
    private var recognizer: PARSEQRecognizer?
    private var readingOrderProcessor: ReadingOrderProcessor?

    func initialize() {
        guard case .uninitialized = state else { return }
        state = .loading
        progress = 0

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try self?.loadModels()
                DispatchQueue.main.async {
                    self?.state = .ready
                    self?.progress = 1.0
                }
            } catch {
                DispatchQueue.main.async {
                    self?.state = .error(error.localizedDescription)
                }
            }
        }
    }

    private func loadModels() throws {
        let env = try ORTEnv(loggingLevel: .warning)
        self.env = env

        // Load config from ndl.yaml
        let config = loadConfig()

        // Load detection model
        guard let detModelPath = Bundle.main.path(forResource: "rtmdet-s-1280x1280", ofType: "onnx", inDirectory: "Models") else {
            throw NSError(domain: "OCR", code: 10, userInfo: [NSLocalizedDescriptionKey: "Detection model not found in bundle"])
        }
        DispatchQueue.main.async { self.progress = 0.1 }

        self.detector = try RTMDetector(
            env: env, modelPath: detModelPath,
            scoreThreshold: config.scoreThreshold,
            nmsThreshold: config.nmsThreshold,
            maxDetections: config.maxDetections
        )
        DispatchQueue.main.async { self.progress = 0.5 }

        // Load recognition model
        guard let recModelPath = Bundle.main.path(forResource: "parseq-ndl-32x384-tiny-10", ofType: "onnx", inDirectory: "Models") else {
            throw NSError(domain: "OCR", code: 11, userInfo: [NSLocalizedDescriptionKey: "Recognition model not found in bundle"])
        }
        guard let charListPath = Bundle.main.path(forResource: "NDLmoji", ofType: "yaml", inDirectory: "Models") else {
            throw NSError(domain: "OCR", code: 12, userInfo: [NSLocalizedDescriptionKey: "NDLmoji.yaml not found in bundle"])
        }

        self.recognizer = try PARSEQRecognizer(env: env, modelPath: recModelPath, charListPath: charListPath)
        DispatchQueue.main.async { self.progress = 0.9 }

        // Reading order
        self.readingOrderProcessor = ReadingOrderProcessor()
        DispatchQueue.main.async { self.progress = 1.0 }
    }

    // MARK: - Config

    private struct Config {
        var scoreThreshold: Float = 0.3
        var nmsThreshold: Float = 0.4
        var maxDetections: Int = 100
        var verticalMode: Bool = true
    }

    private func loadConfig() -> Config {
        var config = Config()
        guard let yamlPath = Bundle.main.path(forResource: "ndl", ofType: "yaml", inDirectory: "Models"),
              let content = try? String(contentsOfFile: yamlPath, encoding: .utf8) else {
            return config
        }

        // Simple YAML parsing for known keys
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("score_threshold:") {
                if let val = Float(trimmed.replacingOccurrences(of: "score_threshold:", with: "").trimmingCharacters(in: .whitespaces)) {
                    config.scoreThreshold = val
                }
            } else if trimmed.hasPrefix("nms_threshold:") {
                if let val = Float(trimmed.replacingOccurrences(of: "nms_threshold:", with: "").trimmingCharacters(in: .whitespaces)) {
                    config.nmsThreshold = val
                }
            } else if trimmed.hasPrefix("max_detections:") {
                if let val = Int(trimmed.replacingOccurrences(of: "max_detections:", with: "").trimmingCharacters(in: .whitespaces)) {
                    config.maxDetections = val
                }
            } else if trimmed.hasPrefix("vertical_mode:") {
                let val = trimmed.replacingOccurrences(of: "vertical_mode:", with: "").trimmingCharacters(in: .whitespaces)
                config.verticalMode = val == "true"
            }
        }

        return config
    }

    // MARK: - Process Image

    func process(image: CGImage) async throws -> OCRResult {
        guard let detector = self.detector,
              let recognizer = self.recognizer,
              let readingOrderProcessor = self.readingOrderProcessor else {
            throw NSError(domain: "OCR", code: 20, userInfo: [NSLocalizedDescriptionKey: "Engine not initialized"])
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    // Step 1: Layout detection
                    var detections = try detector.detect(image: image)

                    // Step 2: Text recognition for each detection
                    for i in 0..<detections.count {
                        let box = detections[i].box
                        let cropRect = CGRect(
                            x: max(0, box[0]),
                            y: max(0, box[1]),
                            width: max(1, box[2] - box[0]),
                            height: max(1, box[3] - box[1])
                        )

                        if let cropped = image.cropping(to: cropRect) {
                            let text = try recognizer.recognize(image: cropped)
                            detections[i].text = text
                        }
                    }

                    // Step 3: Reading order
                    let ordered = readingOrderProcessor.process(
                        detections: detections,
                        imageWidth: image.width,
                        imageHeight: image.height
                    )

                    // Step 4: Combine text
                    let combinedText = ordered.map(\.text).joined(separator: "\n")
                    let result = OCRResult(detections: ordered, text: combinedText)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
