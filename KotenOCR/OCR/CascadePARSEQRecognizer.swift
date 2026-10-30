import Foundation
import CoreGraphics
import OnnxRuntimeBindings

/// Cascade PARSeq recognizer for NDLOCR-Lite mode.
/// Routes each detection to one of three recognizer models based on predCharCount,
/// with fallback to larger models when results are too long.
class CascadePARSEQRecognizer: @unchecked Sendable {
    let recognizer30: PARSEQRecognizer   // 16x256, for predCharCount == 3
    let recognizer50: PARSEQRecognizer   // 16x384, for predCharCount == 2
    let recognizer100: PARSEQRecognizer  // 16x768, for everything else

    init(recognizer30: PARSEQRecognizer, recognizer50: PARSEQRecognizer, recognizer100: PARSEQRecognizer) {
        self.recognizer30 = recognizer30
        self.recognizer50 = recognizer50
        self.recognizer100 = recognizer100
    }

    /// Recognize text from a cropped line image using the cascade strategy.
    /// - Parameters:
    ///   - image: Cropped line image
    ///   - predCharCount: Predicted character count from the detector
    ///   - vertical: Read as a vertical line; nil decides from the crop's shape
    /// - Returns: Recognized text string
    func recognize(image: CGImage, predCharCount: Float, vertical: Bool? = nil) throws -> String {
        let charCount = Int(predCharCount.rounded())

        if charCount == 3 {
            // Try 30-char model first
            let result = try recognizer30.recognize(image: image, vertical: vertical)
            if result.count >= 25 {
                // Too long, fall back to 50-char model
                return try recognizeWith50(image: image, vertical: vertical)
            }
            return result
        } else if charCount == 2 {
            return try recognizeWith50(image: image, vertical: vertical)
        } else {
            return try recognizeWith100(image: image, vertical: vertical)
        }
    }

    private func recognizeWith50(image: CGImage, vertical: Bool?) throws -> String {
        let result = try recognizer50.recognize(image: image, vertical: vertical)
        if result.count >= 45 {
            // Too long, fall back to 100-char model
            return try recognizeWith100(image: image, vertical: vertical)
        }
        return result
    }

    private func recognizeWith100(image: CGImage, vertical: Bool?) throws -> String {
        let result = try recognizer100.recognize(image: image, vertical: vertical)

        // If 100-char model returns 98+ chars AND the line is horizontal (wider than tall), split in half
        if result.count >= 98 && !(vertical ?? (image.height > image.width)) {
            let halfWidth = image.width / 2
            let leftRect = CGRect(x: 0, y: 0, width: halfWidth, height: image.height)
            let rightRect = CGRect(x: halfWidth, y: 0, width: image.width - halfWidth, height: image.height)

            if let leftImage = image.cropping(to: leftRect),
               let rightImage = image.cropping(to: rightRect) {
                let leftText = try recognizer100.recognize(image: leftImage, vertical: false)
                let rightText = try recognizer100.recognize(image: rightImage, vertical: false)
                return leftText + rightText
            }
        }

        return result
    }
}
