import Foundation
import CoreGraphics
import OnnxRuntimeBindings

class DEIMDetector: @unchecked Sendable {
    private let session: ORTSession
    private let inputWidth = 800
    private let inputHeight = 800
    private let confThreshold: Float
    private let maxDetections: Int
    private let classNames: [Int: String]

    struct Metadata {
        let originalWidth: Int
        let originalHeight: Int
        let maxWH: Int
    }

    init(env: ORTEnv, modelPath: String, configPath: String,
         confThreshold: Float = 0.25, maxDetections: Int = 300) throws {
        let options = try ORTSessionOptions()

        self.session = try ORTSession(env: env, modelPath: modelPath, sessionOptions: options)
        self.confThreshold = confThreshold
        self.maxDetections = maxDetections
        self.classNames = DEIMDetector.loadClassNames(from: configPath)
    }

    // MARK: - Load class names from YAML

    static func loadClassNames(from path: String) -> [Int: String] {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return [:]
        }
        var names: [Int: String] = [:]
        var inNames = false
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("names:") {
                inNames = true
                continue
            }
            if inNames {
                // Parse "  0: text_block" format
                let parts = trimmed.split(separator: ":", maxSplits: 1)
                if parts.count == 2, let idx = Int(parts[0].trimmingCharacters(in: .whitespaces)) {
                    names[idx] = parts[1].trimmingCharacters(in: .whitespaces)
                } else if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                    // Reached a non-name entry, stop parsing
                    break
                }
            }
        }
        return names
    }

    // MARK: - Detection

    func detect(image: CGImage) throws -> [Detection] {
        let (tensor, metadata) = preprocess(image: image)
        guard !tensor.isEmpty else { return [] }

        let inputData = NSMutableData(bytes: tensor, length: tensor.count * MemoryLayout<Float>.stride)
        let shape: [NSNumber] = [1, 3, NSNumber(value: inputHeight), NSNumber(value: inputWidth)]
        let inputTensor = try ORTValue(tensorData: inputData, elementType: .float, shape: shape)

        // Second input: orig_target_sizes [1,2] as Int64, values = [inputHeight, inputWidth]
        var sizeValues: [Int64] = [Int64(inputHeight), Int64(inputWidth)]
        let sizeData = NSMutableData(bytes: &sizeValues, length: 2 * MemoryLayout<Int64>.stride)
        let sizeTensor = try ORTValue(tensorData: sizeData, elementType: .int64, shape: [1, 2])

        let inputNames = try session.inputNames()
        guard inputNames.count >= 2 else {
            throw NSError(domain: "OCR", code: 30, userInfo: [NSLocalizedDescriptionKey: "DEIMDetector: expected at least 2 input names"])
        }
        let inputs: [String: ORTValue] = [
            inputNames[0]: inputTensor,
            inputNames[1]: sizeTensor
        ]
        let outputNames = try session.outputNames()
        let results = try session.run(withInputs: inputs, outputNames: Set(outputNames), runOptions: nil)

        return try postprocess(outputs: results, outputNames: outputNames, metadata: metadata)
    }

    // MARK: - Preprocessing

    func preprocess(image: CGImage) -> ([Float], Metadata) {
        let origW = image.width
        let origH = image.height
        let maxWH = max(origW, origH)
        let metadata = Metadata(originalWidth: origW, originalHeight: origH, maxWH: maxWH)

        // Create square context (maxWH x maxWH), fill black, draw image at top-left
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let padCtx = CGContext(data: nil, width: maxWH, height: maxWH,
                                     bitsPerComponent: 8, bytesPerRow: maxWH * 4,
                                     space: colorSpace, bitmapInfo: bitmapInfo) else {
            return ([], metadata)
        }
        padCtx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        padCtx.fill(CGRect(x: 0, y: 0, width: maxWH, height: maxWH))
        // CG has y-up: draw at top = y offset of (maxWH - origH)
        padCtx.draw(image, in: CGRect(x: 0, y: CGFloat(maxWH - origH), width: CGFloat(origW), height: CGFloat(origH)))

        guard let paddedImage = padCtx.makeImage() else { return ([], metadata) }

        // Resize to inputWidth x inputHeight
        guard let resizeCtx = CGContext(data: nil, width: inputWidth, height: inputHeight,
                                        bitsPerComponent: 8, bytesPerRow: inputWidth * 4,
                                        space: colorSpace, bitmapInfo: bitmapInfo) else {
            return ([], metadata)
        }
        resizeCtx.interpolationQuality = .high
        resizeCtx.draw(paddedImage, in: CGRect(x: 0, y: 0, width: inputWidth, height: inputHeight))

        guard let data = resizeCtx.data else { return ([], metadata) }
        let ptr = data.bindMemory(to: UInt8.self, capacity: inputWidth * inputHeight * 4)

        // Build NCHW tensor: divide by 255, subtract ImageNet means, divide by stds
        let means: [Float] = [0.485, 0.456, 0.406]
        let stds: [Float] = [0.229, 0.224, 0.225]
        let pixelCount = inputWidth * inputHeight
        var tensor = [Float](repeating: 0, count: 3 * pixelCount)

        for y in 0..<inputHeight {
            for x in 0..<inputWidth {
                let pixelIdx = (y * inputWidth + x) * 4
                for c in 0..<3 {
                    let value = Float(ptr[pixelIdx + c]) / 255.0
                    tensor[c * pixelCount + y * inputWidth + x] = (value - means[c]) / stds[c]
                }
            }
        }

        return (tensor, metadata)
    }

    // MARK: - Postprocessing

    func postprocess(outputs: [String: ORTValue], outputNames: [String], metadata: Metadata) throws -> [Detection] {
        // Outputs: labels, bboxes, scores, char_counts (4 outputs)
        // or labels, bboxes, scores (3 outputs)
        guard outputNames.count >= 3 else { return [] }

        guard let labelsValue = outputs[outputNames[0]],
              let bboxesValue = outputs[outputNames[1]],
              let scoresValue = outputs[outputNames[2]] else {
            return []
        }

        let labelsData = try labelsValue.tensorData() as Data
        let bboxesData = try bboxesValue.tensorData() as Data
        let scoresData = try scoresValue.tensorData() as Data

        let labels = labelsData.withUnsafeBytes { Array($0.bindMemory(to: Int64.self)) }
        let bboxes = bboxesData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        let scores = scoresData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }

        var charCounts: [Float]?
        if outputNames.count >= 4, let charCountValue = outputs[outputNames[3]] {
            let charCountData = try charCountValue.tensorData() as Data
            charCounts = charCountData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        }

        let numDetections = scores.count
        var detections: [Detection] = []

        // Scale factors: image was padded to maxWH x maxWH, then resized to input size
        // The model outputs bboxes in input coordinates (0..inputWidth, 0..inputHeight)
        // Scale back to padded image (maxWH x maxWH), which maps directly to original coords
        let scaleX = Float(metadata.maxWH) / Float(inputWidth)
        let scaleY = Float(metadata.maxWH) / Float(inputHeight)

        for i in 0..<numDetections {
            let score = scores[i]
            if score < confThreshold { continue }

            let label = Int(labels[i])
            // Python code: class_index = int(label) - 1
            let classIndex = label - 1
            guard classIndex >= 0 else { continue }

            let x1 = bboxes[i * 4 + 0] * scaleX
            let y1 = bboxes[i * 4 + 1] * scaleY
            let x2 = bboxes[i * 4 + 2] * scaleX
            let y2 = bboxes[i * 4 + 3] * scaleY

            let className = classNames[classIndex] ?? "class_\(classIndex)"

            // Clamp and round
            let box: [Int] = [
                max(0, Int(x1.rounded())),
                max(0, Int(y1.rounded())),
                min(metadata.originalWidth, Int(x2.rounded())),
                min(metadata.originalHeight, Int(y2.rounded()))
            ]

            let predCharCount = charCounts?[i] ?? 100.0

            var det = Detection(
                box: box, score: score, classId: classIndex,
                className: className
            )
            det.predCharCount = predCharCount
            detections.append(det)
        }

        // Sort by score descending, limit to maxDetections
        let sorted = detections.sorted { $0.score > $1.score }
        return Array(sorted.prefix(maxDetections))
    }
}
