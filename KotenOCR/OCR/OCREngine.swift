import Foundation
import CoreGraphics
import SwiftUI
import OnnxRuntimeBindings

enum OCREngineState: Equatable {
    case uninitialized
    case loading
    case ready
    case error(String)

    var isReady: Bool { self == .ready }
}

struct OCRResult {
    let detections: [Detection]
    let text: String
}

class OCREngine: ObservableObject {
    @Published var state: OCREngineState = .uninitialized
    @Published var progress: Float = 0
    @AppStorage("ocrMode") var currentModeRaw: String = OCRMode.koten.rawValue

    var currentMode: OCRMode {
        OCRMode(rawValue: currentModeRaw) ?? .koten
    }

    private var env: ORTEnv?

    // Koten mode models
    private var kotenDetector: RTMDetector?
    private var kotenRecognizer: PARSEQRecognizer?

    // NDL mode models
    private var ndlDetector: DEIMDetector?
    private var ndlCascadeRecognizer: CascadePARSEQRecognizer?

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

    /// Switch OCR mode (models are already loaded at startup)
    func switchMode(to mode: OCRMode) {
        currentModeRaw = mode.rawValue
    }

    private func loadModels() throws {
        let env: ORTEnv
        if let existing = self.env {
            env = existing
        } else {
            env = try ORTEnv(loggingLevel: .warning)
            self.env = env
        }

        // Load both model sets at startup
        try loadKotenModels(env: env)
        try loadNDLModels(env: env)

        // Reading order (shared)
        self.readingOrderProcessor = ReadingOrderProcessor()
        DispatchQueue.main.async { self.progress = 1.0 }
    }

    private func loadKotenModels(env: ORTEnv) throws {
        let config = loadConfig(configName: "ndl")

        guard let detModelPath = Bundle.main.path(forResource: "rtmdet-s-1280x1280", ofType: "onnx", inDirectory: "Models") else {
            throw NSError(domain: "OCR", code: 10, userInfo: [NSLocalizedDescriptionKey: "Detection model not found in bundle"])
        }
        DispatchQueue.main.async { self.progress = 0.1 }

        self.kotenDetector = try RTMDetector(
            env: env, modelPath: detModelPath,
            scoreThreshold: config.scoreThreshold,
            nmsThreshold: config.nmsThreshold,
            maxDetections: config.maxDetections
        )
        DispatchQueue.main.async { self.progress = 0.2 }

        guard let recModelPath = Bundle.main.path(forResource: "parseq-ndl-32x384-tiny-10", ofType: "onnx", inDirectory: "Models") else {
            throw NSError(domain: "OCR", code: 11, userInfo: [NSLocalizedDescriptionKey: "Recognition model not found in bundle"])
        }
        guard let charListPath = Bundle.main.path(forResource: "NDLmoji", ofType: "yaml", inDirectory: "Models") else {
            throw NSError(domain: "OCR", code: 12, userInfo: [NSLocalizedDescriptionKey: "NDLmoji.yaml not found in bundle"])
        }

        self.kotenRecognizer = try PARSEQRecognizer(env: env, modelPath: recModelPath, charListPath: charListPath)
        DispatchQueue.main.async { self.progress = 0.3 }
    }

    private func loadNDLModels(env: ORTEnv) throws {
        // Detection model
        guard let detModelPath = Bundle.main.path(forResource: "deim-s-1024x1024", ofType: "onnx", inDirectory: "Models") else {
            throw NSError(domain: "OCR", code: 10, userInfo: [NSLocalizedDescriptionKey: "DEIM detection model not found in bundle"])
        }
        guard let configPath = Bundle.main.path(forResource: "ndl-deim", ofType: "yaml", inDirectory: "Models") else {
            throw NSError(domain: "OCR", code: 13, userInfo: [NSLocalizedDescriptionKey: "ndl-deim.yaml config not found in bundle"])
        }
        DispatchQueue.main.async { self.progress = 0.35 }

        self.ndlDetector = try DEIMDetector(
            env: env, modelPath: detModelPath, configPath: configPath,
            scoreThreshold: 0.2, confThreshold: 0.25,
            iouThreshold: 0.2, maxDetections: 100
        )
        DispatchQueue.main.async { self.progress = 0.5 }

        // Charset (shared across all recognizers)
        guard let charListPath = Bundle.main.path(forResource: "NDLmoji", ofType: "yaml", inDirectory: "Models") else {
            throw NSError(domain: "OCR", code: 12, userInfo: [NSLocalizedDescriptionKey: "NDLmoji.yaml not found in bundle"])
        }

        // Recognition models (3 cascade sizes)
        guard let rec30Path = Bundle.main.path(forResource: "parseq-ndl-16x256-30-tiny-192epoch-tegaki3", ofType: "onnx", inDirectory: "Models") else {
            throw NSError(domain: "OCR", code: 14, userInfo: [NSLocalizedDescriptionKey: "PARSeq 30-char model not found in bundle"])
        }
        guard let rec50Path = Bundle.main.path(forResource: "parseq-ndl-16x384-50-tiny-146epoch-tegaki2", ofType: "onnx", inDirectory: "Models") else {
            throw NSError(domain: "OCR", code: 15, userInfo: [NSLocalizedDescriptionKey: "PARSeq 50-char model not found in bundle"])
        }
        guard let rec100Path = Bundle.main.path(forResource: "parseq-ndl-16x768-100-tiny-165epoch-tegaki2", ofType: "onnx", inDirectory: "Models") else {
            throw NSError(domain: "OCR", code: 16, userInfo: [NSLocalizedDescriptionKey: "PARSeq 100-char model not found in bundle"])
        }

        let recognizer30 = try PARSEQRecognizer(env: env, modelPath: rec30Path, charListPath: charListPath,
                                                  inputWidth: 256, inputHeight: 16)
        DispatchQueue.main.async { self.progress = 0.6 }

        let recognizer50 = try PARSEQRecognizer(env: env, modelPath: rec50Path, charListPath: charListPath,
                                                  inputWidth: 384, inputHeight: 16)
        DispatchQueue.main.async { self.progress = 0.75 }

        let recognizer100 = try PARSEQRecognizer(env: env, modelPath: rec100Path, charListPath: charListPath,
                                                   inputWidth: 768, inputHeight: 16)
        DispatchQueue.main.async { self.progress = 0.9 }

        self.ndlCascadeRecognizer = CascadePARSEQRecognizer(
            recognizer30: recognizer30, recognizer50: recognizer50, recognizer100: recognizer100
        )
    }

    // MARK: - Config

    private struct Config {
        var scoreThreshold: Float = 0.3
        var nmsThreshold: Float = 0.4
        var maxDetections: Int = 100
        var verticalMode: Bool = true
    }

    private func loadConfig(configName: String = "ndl") -> Config {
        var config = Config()
        guard let yamlPath = Bundle.main.path(forResource: configName, ofType: "yaml", inDirectory: "Models"),
              let content = try? String(contentsOfFile: yamlPath, encoding: .utf8) else {
            return config
        }

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
        let mode = currentMode

        switch mode {
        case .koten:
            return try await processKoten(image: image)
        case .ndl:
            return try await processNDL(image: image)
        }
    }

    private func processKoten(image: CGImage) async throws -> OCRResult {
        guard let detector = self.kotenDetector,
              let recognizer = self.kotenRecognizer,
              let readingOrderProcessor = self.readingOrderProcessor else {
            throw NSError(domain: "OCR", code: 20, userInfo: [NSLocalizedDescriptionKey: "Koten engine not initialized"])
        }

        // Step 1: Layout detection
        let detections = try await Task.detached(priority: .userInitiated) {
            try detector.detect(image: image)
        }.value

        try Task.checkCancellation()

        // Step 2: Text recognition for each detection (parallel)
        var recognized = detections
        let results = try await withThrowingTaskGroup(of: (Int, String).self) { group in
            for i in 0..<recognized.count {
                let box = recognized[i].box
                guard box.count >= 4 else { continue }
                let cropRect = CGRect(
                    x: max(0, box[0]),
                    y: max(0, box[1]),
                    width: max(1, box[2] - box[0]),
                    height: max(1, box[3] - box[1])
                )
                guard let cropped = image.cropping(to: cropRect) else { continue }
                group.addTask {
                    let text = try recognizer.recognize(image: cropped)
                    return (i, text)
                }
            }
            var texts: [(Int, String)] = []
            for try await result in group {
                texts.append(result)
            }
            return texts
        }
        for (i, text) in results {
            recognized[i].text = text
        }

        try Task.checkCancellation()

        // Step 3: Reading order
        let ordered = readingOrderProcessor.process(
            detections: recognized,
            imageWidth: image.width,
            imageHeight: image.height
        )

        // Step 4: Combine text
        let combinedText = ordered.map(\.text).joined(separator: "\n")
        return OCRResult(detections: ordered, text: combinedText)
    }

    private func processNDL(image: CGImage) async throws -> OCRResult {
        guard let detector = self.ndlDetector,
              let cascadeRecognizer = self.ndlCascadeRecognizer,
              let readingOrderProcessor = self.readingOrderProcessor else {
            throw NSError(domain: "OCR", code: 20, userInfo: [NSLocalizedDescriptionKey: "NDL engine not initialized"])
        }

        // Step 1: Layout detection
        let allDetections = try await Task.detached(priority: .userInitiated) {
            try detector.detect(image: image)
        }.value

        try Task.checkCancellation()

        // Filter to line_* classes only (text_block and block_* are structural, not for OCR)
        let detections = allDetections.filter { $0.className.hasPrefix("line_") }

        // Step 2: Cascade text recognition for each detection (parallel)
        var recognized = detections
        let results = try await withThrowingTaskGroup(of: (Int, String).self) { group in
            for i in 0..<recognized.count {
                let box = recognized[i].box
                guard box.count >= 4 else { continue }
                let cropRect = CGRect(
                    x: max(0, box[0]),
                    y: max(0, box[1]),
                    width: max(1, box[2] - box[0]),
                    height: max(1, box[3] - box[1])
                )
                guard let cropped = image.cropping(to: cropRect) else { continue }
                let predCharCount = recognized[i].predCharCount

                group.addTask {
                    let text = try cascadeRecognizer.recognize(image: cropped, predCharCount: predCharCount)
                    return (i, text)
                }
            }

            var texts: [(Int, String)] = []
            for try await result in group {
                texts.append(result)
            }
            return texts
        }
        for (i, text) in results {
            recognized[i].text = text
        }

        try Task.checkCancellation()

        // Step 3: Reading order
        let ordered = readingOrderProcessor.process(
            detections: recognized,
            imageWidth: image.width,
            imageHeight: image.height
        )

        // Step 4: Combine text
        let combinedText = ordered.map(\.text).joined(separator: "\n")
        return OCRResult(detections: ordered, text: combinedText)
    }
}
