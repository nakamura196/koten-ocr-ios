import Foundation
import CoreGraphics
import Accelerate
import OnnxRuntimeBindings

struct Detection {
    let box: [Int]       // [x1, y1, x2, y2]
    let score: Float
    let classId: Int
    let className: String
    var text: String = ""
    var id: Int = 0
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

    func detect(image: CGImage) throws -> [Detection] {
        let (tensor, metadata) = preprocess(image: image)
        let inputData = NSMutableData(bytes: tensor, length: tensor.count * MemoryLayout<Float>.stride)
        let shape: [NSNumber] = [1, 3, NSNumber(value: inputHeight), NSNumber(value: inputWidth)]
        let inputTensor = try ORTValue(tensorData: inputData, elementType: .float, shape: shape)

        let inputNames = try session.inputNames()
        let inputs: [String: ORTValue] = [inputNames[0]: inputTensor]
        let outputNames: Set<String> = ["dets", "labels"]
        let results = try session.run(withInputs: inputs, outputNames: outputNames, runOptions: nil)

        return try postprocess(outputs: results, metadata: metadata)
    }

    // MARK: - Preprocessing

    func preprocess(image: CGImage) -> ([Float], Metadata) {
        let origW = image.width
        let origH = image.height
        let maxWH = max(origW, origH)
        let metadata = Metadata(originalWidth: origW, originalHeight: origH, maxWH: maxWH)

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
        var detections: [Detection] = []

        for i in 0..<numDetections {
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
            let box: [Int] = [
                max(0, Int(x1Orig.rounded())),
                max(0, Int(y1Adj.rounded())),
                min(metadata.originalWidth, Int(x2Orig.rounded())),
                min(metadata.originalHeight, Int(y2Adj.rounded()))
            ]

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
