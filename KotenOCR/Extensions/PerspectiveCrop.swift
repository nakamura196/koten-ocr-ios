import CoreGraphics
import CoreImage
import Vision

/// Four corners of a page, in a top-left-origin coordinate space.
/// Used either in image pixels or normalized to 0...1 of the image.
struct Quad: Equatable {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomRight: CGPoint
    var bottomLeft: CGPoint

    static let unit = Quad(topLeft: CGPoint(x: 0, y: 0), topRight: CGPoint(x: 1, y: 0),
                           bottomRight: CGPoint(x: 1, y: 1), bottomLeft: CGPoint(x: 0, y: 1))

    init(topLeft: CGPoint, topRight: CGPoint, bottomRight: CGPoint, bottomLeft: CGPoint) {
        self.topLeft = topLeft; self.topRight = topRight
        self.bottomRight = bottomRight; self.bottomLeft = bottomLeft
    }

    /// Builds a quad from four points in any order (top-left origin).
    /// TL has the smallest x+y, BR the largest x+y, TR the largest x-y, BL the smallest x-y.
    init?(normalizing points: [CGPoint]) {
        guard points.count == 4 else { return nil }
        let tl = points.min { $0.x + $0.y < $1.x + $1.y }!
        let br = points.max { $0.x + $0.y < $1.x + $1.y }!
        let tr = points.max { $0.x - $0.y < $1.x - $1.y }!
        let bl = points.min { $0.x - $0.y < $1.x - $1.y }!
        guard Set([tl, br, tr, bl].map { "\($0.x),\($0.y)" }).count == 4 else { return nil }
        self.init(topLeft: tl, topRight: tr, bottomRight: br, bottomLeft: bl)
    }

    init(rect: CGRect) {
        self.init(topLeft: CGPoint(x: rect.minX, y: rect.minY), topRight: CGPoint(x: rect.maxX, y: rect.minY),
                  bottomRight: CGPoint(x: rect.maxX, y: rect.maxY), bottomLeft: CGPoint(x: rect.minX, y: rect.maxY))
    }

    var points: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }

    func map(_ f: (CGPoint) -> CGPoint) -> Quad {
        Quad(topLeft: f(topLeft), topRight: f(topRight), bottomRight: f(bottomRight), bottomLeft: f(bottomLeft))
    }

    func scaled(to size: CGSize) -> Quad {
        map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
    }

    /// Size of the rectified page: the longer of each pair of opposite edges.
    var rectifiedSize: CGSize {
        func d(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
        return CGSize(width: max(d(topLeft, topRight), d(bottomLeft, bottomRight)),
                      height: max(d(topLeft, bottomLeft), d(topRight, bottomRight)))
    }

    /// True when the quad is convex, non-degenerate and has a consistent winding.
    var isConvex: Bool {
        let p = points
        var sign: CGFloat = 0
        for i in 0..<4 {
            let a = p[i], b = p[(i + 1) % 4], c = p[(i + 2) % 4]
            let cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
            if abs(cross) < 1e-9 { return false }
            if sign == 0 { sign = cross > 0 ? 1 : -1 } else if (cross > 0) != (sign > 0) { return false }
        }
        return true
    }

    var boundingRect: CGRect {
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }
}

enum PerspectiveCrop {
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Rectifies the area inside `quad` (normalized 0...1, top-left origin) into an upright image.
    /// Returns nil when the quad is not convex or too small.
    static func rectify(_ image: CGImage, normalizedQuad: Quad) -> CGImage? {
        let size = CGSize(width: image.width, height: image.height)
        return rectify(image, pixelQuad: normalizedQuad.scaled(to: size))
    }

    static func rectify(_ image: CGImage, pixelQuad q: Quad) -> CGImage? {
        guard q.isConvex else { return nil }
        let out = q.rectifiedSize
        guard out.width >= 8, out.height >= 8 else { return nil }
        let h = CGFloat(image.height)
        // Core Image uses a bottom-left origin.
        func ci(_ p: CGPoint) -> CIVector { CIVector(x: p.x, y: h - p.y) }
        let input = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(ci(q.topLeft), forKey: "inputTopLeft")
        filter.setValue(ci(q.topRight), forKey: "inputTopRight")
        filter.setValue(ci(q.bottomRight), forKey: "inputBottomRight")
        filter.setValue(ci(q.bottomLeft), forKey: "inputBottomLeft")
        guard let result = filter.outputImage, !result.extent.isInfinite, !result.extent.isEmpty else { return nil }
        guard let corrected = ciContext.createCGImage(result, from: result.extent) else { return nil }
        // CIPerspectiveCorrection does not guarantee the output size/aspect, so resample to the size
        // implied by the quad's edge lengths.
        let w = Int(out.width.rounded()), h2 = Int(out.height.rounded())
        if abs(corrected.width - w) <= 1 && abs(corrected.height - h2) <= 1 { return corrected }
        guard let ctx = CGContext(data: nil, width: w, height: h2, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return corrected }
        ctx.interpolationQuality = .high
        ctx.draw(corrected, in: CGRect(x: 0, y: 0, width: w, height: h2))
        return ctx.makeImage() ?? corrected
    }

    /// The page found in the background replaces the corners only while they are still the ones it
    /// started from. Detection on a large photo can finish after the reader has dragged a corner;
    /// overwriting then threw their adjustment away, and the crop did not match what they set.
    static func adoptDetected(_ found: Quad, current: Quad, seeded: Quad) -> Quad {
        current == seeded ? found : current
    }

    enum DetectionMethod { case rectangles, documentSegmentation }

    /// Looks for a page-like rectangle. Returns a normalized quad (top-left origin) or nil.
    static func detectPage(in image: CGImage, minimumConfidence: Float = 0.7) -> Quad? {
        detectPageWithConfidence(in: image, method: .rectangles, minimumConfidence: minimumConfidence)?.quad
    }

    /// Finds the page with the chosen Vision request. `.documentSegmentation` is the model behind
    /// the system document scanner (iOS 15+); `.rectangles` is the older edge-based search.
    static func detectPageWithConfidence(in image: CGImage, method: DetectionMethod,
                                         minimumConfidence: Float = 0.7) -> (quad: Quad, confidence: Float)? {
        let request: VNImageBasedRequest
        switch method {
        case .rectangles:
            let r = VNDetectRectanglesRequest()
            r.minimumConfidence = minimumConfidence
            r.minimumAspectRatio = 0.3
            r.minimumSize = 0.3
            r.quadratureTolerance = 30
            r.maximumObservations = 1
            request = r
        case .documentSegmentation:
            request = VNDetectDocumentSegmentationRequest()
        }
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil,
              let obs = (request.results as? [VNRectangleObservation])?.first,
              obs.confidence >= minimumConfidence else { return nil }
        // Vision is bottom-left origin; flip y.
        func f(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: 1 - p.y) }
        guard let q = Quad(normalizing: [f(obs.topLeft), f(obs.topRight), f(obs.bottomRight), f(obs.bottomLeft)])
        else { return nil }
        return (q, obs.confidence)
    }

    /// True when the quad is (nearly) the whole frame, e.g. the outer edge of a scan. Rectifying it
    /// gains nothing, so the crop screen should not switch to four-corner mode for it.
    static func isNearlyFullFrame(_ q: Quad, tolerance: CGFloat = 0.03) -> Bool {
        let u = Quad.unit
        return zip(q.points, u.points).allSatisfy { abs($0.x - $1.x) <= tolerance && abs($0.y - $1.y) <= tolerance }
    }

    /// Whether a detected page is worth rectifying (a convex shape that is not just the frame).
    static func isUsableDetection(_ q: Quad) -> Bool {
        q.isConvex && !isNearlyFullFrame(q)
    }

    /// Detection behind the crop screen's 自動補正: the document-scanner model (it also finds a
    /// tilted sheet photographed on a table, which the rectangle search misses).
    /// The simulator runs that model differently and returns a bogus strip along the bottom edge,
    /// so there it falls back to the rectangle search to keep screenshots and UI tests meaningful.
    static func detectForCropScreen(in image: CGImage) -> Quad? {
        #if targetEnvironment(simulator)
        return detectPageWithConfidence(in: image, method: .rectangles)?.quad
        #else
        return detectPageWithConfidence(in: image, method: .documentSegmentation)?.quad
        #endif
    }
}
