import Foundation
import CoreGraphics
import Accelerate
import OnnxRuntimeBindings

struct Detection: Codable {
    let box: [Int]       // [x1, y1, x2, y2]
    var score: Float
    let classId: Int
    let className: String
    var text: String = ""
    var id: Int = 0
    var predCharCount: Float = 100.0

    enum CodingKeys: String, CodingKey {
        case box, score, classId, className, text, id, predCharCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        box = try container.decode([Int].self, forKey: .box)
        score = try container.decode(Float.self, forKey: .score)
        classId = try container.decode(Int.self, forKey: .classId)
        className = try container.decode(String.self, forKey: .className)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        id = try container.decodeIfPresent(Int.self, forKey: .id) ?? 0
        predCharCount = try container.decodeIfPresent(Float.self, forKey: .predCharCount) ?? 100.0
    }

    init(box: [Int], score: Float, classId: Int, className: String,
         text: String = "", id: Int = 0, predCharCount: Float = 100.0) {
        self.box = box
        self.score = score
        self.classId = classId
        self.className = className
        self.text = text
        self.id = id
        self.predCharCount = predCharCount
    }

    /// NDL layout classes that hold one line of text (`line_main`, `line_title`, ...),
    /// as opposed to structural ones (`text_block`, `block_*`).
    var isTextLine: Bool { className.hasPrefix("line_") }

    /// Clamps a model box into the image on both sides and converts it to pixels. Returns nil when
    /// nothing of it is left (it lay outside the image or was inverted) or a coordinate is not finite.
    /// Only the lower edge used to be clamped for x1/y1 and only the upper for x2/y2, so a box past
    /// the right edge or above the top came out inverted or with negative coordinates.
    static func clampedBox(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float,
                           width: Int, height: Int, rounding: FloatingPointRoundingRule) -> [Int]? {
        guard x1.isFinite, y1.isFinite, x2.isFinite, y2.isFinite else { return nil }
        let w = Float(width), h = Float(height)
        let box = [min(max(0, x1), w), min(max(0, y1), h), min(max(0, x2), w), min(max(0, y2), h)]
            .map { Int($0.rounded(rounding)) }
        guard box[2] > box[0], box[3] > box[1] else { return nil }
        return box
    }
}

class RTMDetector: @unchecked Sendable {
    private let session: ORTSession
    private let inputWidth = 1024
    private let inputHeight = 1024
    private let scoreThreshold: Float
    private let nmsThreshold: Float
    private let maxDetections: Int

    struct Metadata {
        let originalWidth: Int
        let originalHeight: Int
        let maxWH: Int
    }

    init(env: ORTEnv, modelPath: String, scoreThreshold: Float = 0.3,
         nmsThreshold: Float = 0.4, maxDetections: Int = 100) throws {
        let options = try ORTSessionOptions()

        self.session = try ORTSession(env: env, modelPath: modelPath, sessionOptions: options)
        self.scoreThreshold = scoreThreshold
        self.nmsThreshold = nmsThreshold
        self.maxDetections = maxDetections
    }

    /// The ORT values, output dictionary and tensor data are autoreleased Objective-C objects.
    /// Swift concurrency threads drain their autorelease pool rarely, so without a pool per run
    /// every run's output buffers stayed alive and the footprint grew with each image.
    func detect(image: CGImage) throws -> [Detection] {
        try autoreleasepool { try detectUnpooled(image: image) }
    }

    private func detectUnpooled(image: CGImage) throws -> [Detection] {
        let (tensor, metadata) = preprocess(image: image)
        let inputData = NSMutableData(bytes: tensor, length: tensor.count * MemoryLayout<Float>.stride)
        let shape: [NSNumber] = [1, 3, NSNumber(value: inputHeight), NSNumber(value: inputWidth)]
        let inputTensor = try ORTValue(tensorData: inputData, elementType: .float, shape: shape)

        let inputNames = try session.inputNames()
        guard let firstInputName = inputNames.first else {
            throw NSError(domain: "OCR", code: 30, userInfo: [NSLocalizedDescriptionKey: "RTMDetector: no input names"])
        }
        let inputs: [String: ORTValue] = [firstInputName: inputTensor]
        let outputNames: Set<String> = ["dets", "labels"]
        let results = try session.run(withInputs: inputs, outputNames: outputNames, runOptions: ORTMemory.runOptions())

        return try postprocess(outputs: results, metadata: metadata)
    }

    // MARK: - Preprocessing

    func preprocess(image: CGImage) -> ([Float], Metadata) {
        let origW = image.width
        let origH = image.height
        let maxWH = max(origW, origH)
        let metadata = Metadata(originalWidth: origW, originalHeight: origH, maxWH: maxWH)
        guard maxWH > 0 else { return ([], metadata) }

        // Create 1280x1280 context, fill black, draw padded+resized image
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: nil, width: inputWidth, height: inputHeight,
                                  bitsPerComponent: 8, bytesPerRow: inputWidth * 4,
                                  space: colorSpace, bitmapInfo: bitmapInfo) else {
            return ([], metadata)
        }

        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: inputWidth, height: inputHeight))
        ctx.interpolationQuality = .high

        // Scale to fit in 1280x1280 while maintaining aspect ratio via padding
        let drawW = CGFloat(origW) * CGFloat(inputWidth) / CGFloat(maxWH)
        let drawH = CGFloat(origH) * CGFloat(inputHeight) / CGFloat(maxWH)
        // CG has y-up, so put image at top = high y values
        ctx.draw(image, in: CGRect(x: 0, y: CGFloat(inputHeight) - drawH, width: drawW, height: drawH))

        guard let data = ctx.data else { return ([], metadata) }
        let ptr = data.bindMemory(to: UInt8.self, capacity: inputWidth * inputHeight * 4)

        // Build NCHW tensor with normalization
        // CGBitmapContext stores pixels top-to-bottom (row 0 = visual top)
        let means: [Float] = [123.675, 116.28, 103.53]
        let stds: [Float] = [58.395, 57.12, 57.375]
        let pixelCount = inputWidth * inputHeight
        var tensor = [Float](repeating: 0, count: 3 * pixelCount)

        for y in 0..<inputHeight {
            for x in 0..<inputWidth {
                let pixelIdx = (y * inputWidth + x) * 4
                for c in 0..<3 {
                    let value = Float(ptr[pixelIdx + c])
                    tensor[c * pixelCount + y * inputWidth + x] = (value - means[c]) / stds[c]
                }
            }
        }

        return (tensor, metadata)
    }

    // MARK: - Postprocessing

    func postprocess(outputs: [String: ORTValue], metadata: Metadata) throws -> [Detection] {
        guard let detsValue = outputs["dets"], let labelsValue = outputs["labels"] else {
            return []
        }

        let detsData = try detsValue.tensorData() as Data
        let labelsData = try labelsValue.tensorData() as Data

        let dets = detsData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        let labels = labelsData.withUnsafeBytes { Array($0.bindMemory(to: Int64.self)) }

        let numDetections = dets.count / 5
        guard dets.count >= 5, labels.count >= numDetections else {
            return []
        }
        var detections: [Detection] = []

        for i in 0..<numDetections {
            guard i < labels.count else { break }
            let score = dets[i * 5 + 4]
            if score < scoreThreshold { continue }

            let x1Norm = dets[i * 5 + 0]
            let y1Norm = dets[i * 5 + 1]
            let x2Norm = dets[i * 5 + 2]
            let y2Norm = dets[i * 5 + 3]
            let classId = Int(labels[i])

            // Scale back to original coordinates
            let x1Orig = x1Norm / Float(inputWidth) * Float(metadata.maxWH)
            let y1Orig = y1Norm / Float(inputHeight) * Float(metadata.maxWH)
            let x2Orig = x2Norm / Float(inputWidth) * Float(metadata.maxWH)
            let y2Orig = y2Norm / Float(inputHeight) * Float(metadata.maxWH)

            // Expand height by 2%
            let boxHeight = y2Orig - y1Orig
            let verticalPad = boxHeight * 0.02
            let y1Adj = y1Orig - verticalPad
            let y2Adj = y2Orig + verticalPad

            // Clamp and round
            guard let box = Detection.clampedBox(x1Orig, y1Adj, x2Orig, y2Adj,
                                                 width: metadata.originalWidth, height: metadata.originalHeight,
                                                 rounding: .toNearestOrAwayFromZero) else { continue }

            detections.append(Detection(
                box: box, score: score, classId: classId,
                className: classId == 0 ? "text" : "class_\(classId)"
            ))
        }

        // No NMS needed: ONNX model outputs post-NMS results
        // Limit to maxDetections, sorted by score descending
        let sorted = detections.sorted { $0.score > $1.score }
        return Array(sorted.prefix(maxDetections))
    }
}
