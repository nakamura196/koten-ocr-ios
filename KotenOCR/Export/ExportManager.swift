import Foundation
import UIKit
import CoreText

struct ExportManager {

    static func exportAsTXT(text: String, fileName: String = "KotenOCR") -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("\(fileName).txt")
        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            return nil
        }
    }

    static func exportAsPDF(text: String, image: CGImage?, fileName: String = "KotenOCR") -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("\(fileName).pdf")

        let pageWidth: CGFloat = 595.0  // A4
        let pageHeight: CGFloat = 842.0
        let margin: CGFloat = 40.0
        let textAreaWidth = pageWidth - margin * 2
        let textAreaHeight = pageHeight - margin * 2

        UIGraphicsBeginPDFContextToFile(fileURL.path, CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight), nil)

        // Page 1: Image (if available)
        if let image = image {
            UIGraphicsBeginPDFPage()
            let uiImage = UIImage(cgImage: image)
            let availableWidth = pageWidth - margin * 2
            let availableHeight = pageHeight - margin * 2
            let imageAspect = uiImage.size.width / uiImage.size.height
            let availableAspect = availableWidth / availableHeight

            var drawRect: CGRect
            if imageAspect > availableAspect {
                let w = availableWidth
                let h = w / imageAspect
                drawRect = CGRect(x: margin, y: margin, width: w, height: h)
            } else {
                let h = availableHeight
                let w = h * imageAspect
                drawRect = CGRect(x: margin, y: margin, width: w, height: h)
            }
            uiImage.draw(in: drawRect)
        }

        // Page 2+: Text
        if !text.isEmpty {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 4
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14),
                .paragraphStyle: paragraphStyle
            ]

            let attrString = NSAttributedString(string: text, attributes: attributes)
            let framesetter = CTFramesetterCreateWithAttributedString(attrString)
            var textPosition = 0
            let totalLength = attrString.length

            while textPosition < totalLength {
                UIGraphicsBeginPDFPage()
                guard let context = UIGraphicsGetCurrentContext() else { break }

                // CoreText uses a flipped coordinate system (origin at bottom-left)
                context.saveGState()
                context.translateBy(x: 0, y: pageHeight)
                context.scaleBy(x: 1.0, y: -1.0)

                let textRect = CGRect(x: margin, y: margin, width: textAreaWidth, height: textAreaHeight)
                let path = CGPath(rect: textRect, transform: nil)
                let frameRange = CFRange(location: textPosition, length: 0)
                let frame = CTFramesetterCreateFrame(framesetter, frameRange, path, nil)
                CTFrameDraw(frame, context)

                context.restoreGState()

                let visibleRange = CTFrameGetVisibleStringRange(frame)
                if visibleRange.length == 0 {
                    break  // Prevent infinite loop
                }
                textPosition += visibleRange.length
            }
        }

        UIGraphicsEndPDFContext()
        return fileURL
    }
}
