import Foundation
import CoreGraphics
import OnnxRuntimeBindings

class PARSEQRecognizer: @unchecked Sendable {
    private let session: ORTSession
    private let charList: [Character]
    private let inputWidth = 384
    private let inputHeight = 32

    init(env: ORTEnv, modelPath: String, charListPath: String) throws {
        let options = try ORTSessionOptions()
        self.session = try ORTSession(env: env, modelPath: modelPath, sessionOptions: options)
        self.charList = try PARSEQRecognizer.loadCharset(from: charListPath)
    }

    // MARK: - Charset Loading

    static func loadCharset(from yamlPath: String) throws -> [Character] {
        let content = try String(contentsOfFile: yamlPath, encoding: .utf8)
        guard let keyRange = content.range(of: "charset_train:") else {
            throw NSError(domain: "OCR", code: 1, userInfo: [NSLocalizedDescriptionKey: "charset_train not found in YAML"])
        }
        let afterKey = content[keyRange.upperBound...]
        guard let firstQuote = afterKey.firstIndex(of: "\"") else {
            throw NSError(domain: "OCR", code: 2, userInfo: [NSLocalizedDescriptionKey: "charset_train value not quoted"])
        }
        let afterFirstQuote = afterKey[afterKey.index(after: firstQuote)...]

        var result = ""
        var escaped = false
        for char in afterFirstQuote {
            if escaped {
                switch char {
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                case "n": result.append("\n")
                case "t": result.append("\t")
                default: result.append(char)
                }
                escaped = false
            } else if char == "\\" {
                escaped = true
            } else if char == "\"" {
                break
            } else {
                result.append(char)
            }
        }

        return Array(result)
    }

    // MARK: - Recognition

    func recognize(image: CGImage) throws -> String {
        let tensor = preprocess(image: image)
        let inputData = NSMutableData(bytes: tensor, length: tensor.count * MemoryLayout<Float>.stride)
        let shape: [NSNumber] = [1, 3, NSNumber(value: inputHeight), NSNumber(value: inputWidth)]
        let inputTensor = try ORTValue(tensorData: inputData, elementType: .float, shape: shape)

        let inputNames = try session.inputNames()
        let outputNames = try session.outputNames()
        let inputs: [String: ORTValue] = [inputNames[0]: inputTensor]
        let results = try session.run(withInputs: inputs, outputNames: Set(outputNames), runOptions: nil)

        return try postprocess(outputs: results, outputName: outputNames[0])
    }

    // MARK: - Preprocessing

    func preprocess(image: CGImage) -> [Float] {
        var width = image.width
        var height = image.height
        var pixels = extractPixels(from: image)

        // Rotate if image is taller than wide (vertical text)
        if height > width {
            (pixels, width, height) = rotatePixels90CCW(pixels: pixels, width: width, height: height)
        }

        // Resize to inputWidth x inputHeight (384 x 32)
        let resizedPixels = resizePixels(pixels: pixels, srcWidth: width, srcHeight: height,
                                         dstWidth: inputWidth, dstHeight: inputHeight)

        // Normalize to [-1, 1] and convert to NCHW
        let pixelCount = inputWidth * inputHeight
        var tensor = [Float](repeating: 0, count: 3 * pixelCount)

        for y in 0..<inputHeight {
            for x in 0..<inputWidth {
                let pixelIdx = (y * inputWidth + x) * 4
                for c in 0..<3 {
                    let value = Float(resizedPixels[pixelIdx + c])
                    tensor[c * pixelCount + y * inputWidth + x] = value / 127.5 - 1.0
                }
            }
        }

        return tensor
    }

    // MARK: - Pixel Extraction

    func extractPixels(from image: CGImage) -> [UInt8] {
        let width = image.width
        let height = image.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        guard let ctx = CGContext(data: &pixels, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return pixels
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // CGBitmapContext stores pixels top-to-bottom (row 0 = visual top)
        return pixels
    }

    // MARK: - Rotation (counterclockwise 90 degrees, matching JS -Math.PI/2)

    func rotatePixels90CCW(pixels: [UInt8], width: Int, height: Int) -> ([UInt8], Int, Int) {
        let newWidth = height
        let newHeight = width
        var rotated = [UInt8](repeating: 0, count: newWidth * newHeight * 4)

        for y in 0..<height {
            for x in 0..<width {
                let srcIdx = (y * width + x) * 4
                let newX = y
                let newY = width - 1 - x
                let dstIdx = (newY * newWidth + newX) * 4
                rotated[dstIdx] = pixels[srcIdx]
                rotated[dstIdx + 1] = pixels[srcIdx + 1]
                rotated[dstIdx + 2] = pixels[srcIdx + 2]
                rotated[dstIdx + 3] = pixels[srcIdx + 3]
            }
        }

        return (rotated, newWidth, newHeight)
    }

    // MARK: - Resize

    func resizePixels(pixels: [UInt8], srcWidth: Int, srcHeight: Int,
                      dstWidth: Int, dstHeight: Int) -> [UInt8] {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        // Pixels are already in top-down order (matching CGBitmapContext layout)
        var srcPixels = pixels
        guard let srcCtx = CGContext(data: &srcPixels, width: srcWidth, height: srcHeight,
                                     bitsPerComponent: 8, bytesPerRow: srcWidth * 4,
                                     space: colorSpace, bitmapInfo: bitmapInfo),
              let srcImage = srcCtx.makeImage() else {
            return [UInt8](repeating: 0, count: dstWidth * dstHeight * 4)
        }

        // Draw resized into destination context
        var dstPixels = [UInt8](repeating: 0, count: dstWidth * dstHeight * 4)
        guard let dstCtx = CGContext(data: &dstPixels, width: dstWidth, height: dstHeight,
                                     bitsPerComponent: 8, bytesPerRow: dstWidth * 4,
                                     space: colorSpace, bitmapInfo: bitmapInfo) else {
            return dstPixels
        }
        dstCtx.interpolationQuality = .high
        dstCtx.draw(srcImage, in: CGRect(x: 0, y: 0, width: dstWidth, height: dstHeight))
        return dstPixels
    }

    // MARK: - Postprocessing

    func postprocess(outputs: [String: ORTValue], outputName: String) throws -> String {
        guard let output = outputs[outputName] else { return "" }
        let data = try output.tensorData() as Data
        let info = try output.tensorTypeAndShapeInfo()
        let shape = info.shape.map { $0.intValue }  // [batch, seqLen, vocabSize]

        let floats = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }

        guard shape.count == 3 else { return "" }
        let seqLen = shape[1]
        let vocabSize = shape[2]

        // Greedy decode (autoregressive, no CTC dedup needed)
        var result: [Character] = []
        for t in 0..<seqLen {
            let offset = t * vocabSize
            var maxIdx = 0
            var maxVal: Float = -Float.infinity
            for v in 0..<vocabSize {
                let val = floats[offset + v]
                if val > maxVal {
                    maxVal = val
                    maxIdx = v
                }
            }

            // Index 0 = EOS → stop
            if maxIdx == 0 { break }
            // Map to charset: charList[maxIdx - 1]
            let charIdx = maxIdx - 1
            if charIdx >= 0 && charIdx < charList.count {
                result.append(charList[charIdx])
            }
        }

        return String(result)
    }
}
