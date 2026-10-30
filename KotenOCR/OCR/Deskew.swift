import CoreGraphics
import Foundation

/// Small-angle (±10°) skew estimation and correction, applied before text detection.
///
/// Angle convention (pixel coordinates, y pointing down): a positive angle means a text line that
/// should be vertical runs from top-left to bottom-right, i.e. `x = x0 + y * tan(angle)`.
/// Visually the page content has been rotated counter-clockwise by `angle`.
///
/// Method: projection profiles. The image is downscaled to ~1000px, ink pixels are found with an
/// adaptive (local-mean) threshold, and for each candidate angle the ink pixels are projected onto
/// the axis perpendicular to the text lines. The angle whose histogram is sharpest (largest sum of
/// squares) is the skew. Coarse search at 0.5°, then fine search at 0.1°.
enum Deskew {
    /// UserDefaults key for the 「傾きを自動補正」 setting (default ON).
    static let settingsKey = "autoDeskew"

    static var isEnabled: Bool {
        // bool(forKey:) also understands "NO"/"YES" strings from launch arguments.
        UserDefaults.standard.object(forKey: settingsKey) == nil ? true : UserDefaults.standard.bool(forKey: settingsKey)
    }

    enum TextOrientation {
        /// Vertical text columns (古典籍). Only the column profile is used.
        case vertical
        /// Horizontal text rows. Only the row profile is used.
        case horizontal
        /// Try both and keep the orientation with the sharper profile.
        case auto
    }

    struct Estimate {
        /// Estimated skew in degrees (see convention above).
        let angle: Double
        /// Profile score at `angle` divided by the score at 0°. 1.0 means "no better than straight".
        let gain: Double
        /// Number of ink pixels used.
        let inkPixels: Int
        /// Estimated paper colour (RGB 0...1), used to fill the corners after rotation.
        let paperColor: (r: Double, g: Double, b: Double)

        /// Rotate only when the tilt is noticeable and clearly better than leaving the page as is.
        var shouldRotate: Bool {
            abs(angle) >= Deskew.minAngle && gain >= Deskew.minGain && inkPixels >= Deskew.minInkPixels
        }
    }

    static let maxAngle = 10.0
    static let minAngle = 0.3
    static let minGain = 1.01
    static let minInkPixels = 200
    static let workingLongSide = 1000
    static let maxPoints = 80_000

    // MARK: - Public API

    /// Estimate the skew and, if worthwhile, return the rotated image. The returned image is the
    /// one OCR should run on and the one shown/saved with the result.
    static func deskew(_ image: CGImage, orientation: TextOrientation) -> (image: CGImage, angle: Double) {
        guard let est = estimateSkew(image, orientation: orientation), est.shouldRotate,
              let rotated = rotate(image, byDegrees: -est.angle, fill: est.paperColor) else {
            return (image, 0)
        }
        return (rotated, est.angle)
    }

    static func estimateSkew(_ image: CGImage, orientation: TextOrientation = .auto) -> Estimate? {
        guard let small = downscaleRGBA(image) else { return nil }
        let w = small.width, h = small.height
        let px = small.pixels

        // Grayscale + integral image (for the local mean), using raw buffers for speed
        let iw = w + 1
        var gray = [UInt8](repeating: 0, count: w * h)
        var integral = [UInt32](repeating: 0, count: iw * (h + 1))
        px.withUnsafeBufferPointer { pp in
            gray.withUnsafeMutableBufferPointer { gp in
                integral.withUnsafeMutableBufferPointer { ip in
                    for y in 0..<h {
                        var rowSum: UInt32 = 0
                        for x in 0..<w {
                            let i = y * w + x
                            let v = (UInt32(pp[i * 4]) * 299 + UInt32(pp[i * 4 + 1]) * 587
                                     + UInt32(pp[i * 4 + 2]) * 114) / 1000
                            gp[i] = UInt8(v)
                            rowSum += v
                            ip[(y + 1) * iw + (x + 1)] = ip[y * iw + (x + 1)] + rowSum
                        }
                    }
                }
            }
        }

        // Ink pixels: darker than 85% of the local mean (adaptive threshold, robust to shading and
        // to large dark areas such as a table around the page, whose interior is not "ink").
        let radius = max(7, max(w, h) / 40)
        let margin = max(2, Int(0.015 * Double(max(w, h))))  // ignore photo / crop borders
        var xs: [Float] = []
        var ys: [Float] = []
        xs.reserveCapacity(w * h / 8)
        ys.reserveCapacity(w * h / 8)
        var paperSum = (r: 0.0, g: 0.0, b: 0.0), paperCount = 0.0
        let cx = Float(w) / 2, cy = Float(h) / 2

        px.withUnsafeBufferPointer { pp in
            gray.withUnsafeBufferPointer { gp in
                integral.withUnsafeBufferPointer { ip in
                    for y in 0..<h {
                        let y0 = max(0, y - radius), y1 = min(h, y + radius + 1)
                        let inYMargin = y >= margin && y < h - margin
                        let inYCenter = y > h / 5 && y < h * 4 / 5
                        for x in 0..<w {
                            let x0 = max(0, x - radius), x1 = min(w, x + radius + 1)
                            let sum = Int(ip[y1 * iw + x1]) - Int(ip[y0 * iw + x1])
                                - Int(ip[y1 * iw + x0]) + Int(ip[y0 * iw + x0])
                            let area = (y1 - y0) * (x1 - x0)
                            let g = Int(gp[y * w + x])
                            // g < mean * 0.85 - 4, in integers
                            if g * area * 100 < sum * 85 - 400 * area {
                                if inYMargin, x >= margin, x < w - margin {
                                    xs.append(Float(x) - cx)
                                    ys.append(Float(y) - cy)
                                }
                            } else if inYCenter, g * area >= sum, x > w / 5, x < w * 4 / 5 {
                                let i = (y * w + x) * 4
                                paperSum.r += Double(pp[i]); paperSum.g += Double(pp[i + 1]); paperSum.b += Double(pp[i + 2])
                                paperCount += 1
                            }
                        }
                    }
                }
            }
        }

        // Cap the number of points: the profile shape does not need more, and this bounds the cost.
        if xs.count > maxPoints {
            let step = Double(xs.count) / Double(maxPoints)
            var sx: [Float] = [], sy: [Float] = []
            sx.reserveCapacity(maxPoints); sy.reserveCapacity(maxPoints)
            var k = 0.0
            while Int(k) < xs.count { sx.append(xs[Int(k)]); sy.append(ys[Int(k)]); k += step }
            xs = sx; ys = sy
        }

        let paper: (r: Double, g: Double, b: Double) = paperCount > 0
            ? (paperSum.r / paperCount / 255, paperSum.g / paperCount / 255, paperSum.b / paperCount / 255)
            : (1, 1, 1)
        let n = xs.count
        guard n >= minInkPixels else {
            return Estimate(angle: 0, gain: 1, inkPixels: n, paperColor: paper)
        }

        let bins = Int((Double(w * w + h * h)).squareRoot()) + 2
        var hist = [Int32](repeating: 0, count: bins)

        func score(_ deg: Double, vertical: Bool) -> Double {
            let t = deg * .pi / 180
            let c = Float(cos(t)), s = Float(sin(t))
            let offset = Float(bins / 2)
            hist.withUnsafeMutableBufferPointer { hp in hp.update(repeating: 0) }
            xs.withUnsafeBufferPointer { xp in
                ys.withUnsafeBufferPointer { yp in
                    hist.withUnsafeMutableBufferPointer { hp in
                        for i in 0..<n {
                            // vertical lines: u = x cos - y sin is constant along a line tilted by +deg
                            let u = vertical ? (xp[i] * c - yp[i] * s) : (xp[i] * s + yp[i] * c)
                            let k = min(bins - 1, max(0, Int((u + offset).rounded(.down))))
                            hp[k] += 1
                        }
                    }
                }
            }
            var sum = 0.0
            hist.withUnsafeBufferPointer { hp in
                for v in hp { sum += Double(v) * Double(v) }
            }
            return sum
        }

        func search(vertical: Bool) -> (angle: Double, best: Double, zero: Double) {
            var bestAngle = 0.0, best = -1.0
            for k in -20...20 {
                let d = Double(k) * 0.5
                let sc = score(d, vertical: vertical)
                if sc > best { best = sc; bestAngle = d }
            }
            let coarse = bestAngle
            for k in -5...5 where k != 0 {
                let d = coarse + Double(k) * 0.1
                let sc = score(d, vertical: vertical)
                if sc > best { best = sc; bestAngle = d }
            }
            let zero = score(0, vertical: vertical)
            return ((bestAngle * 10).rounded() / 10, best, zero)
        }

        let result: (angle: Double, best: Double, zero: Double)
        switch orientation {
        case .vertical: result = search(vertical: true)
        case .horizontal: result = search(vertical: false)
        case .auto:
            let v = search(vertical: true), hz = search(vertical: false)
            result = v.best >= hz.best ? v : hz
        }
        let gain = result.zero > 0 ? result.best / result.zero : 1
        return Estimate(angle: result.angle, gain: gain, inkPixels: n, paperColor: paper)
    }

    /// Rotate the image visually by `degrees` (positive = counter-clockwise), expanding the canvas so
    /// nothing is cut off and filling the new corners with `fill` so no dark wedges appear.
    static func rotate(_ image: CGImage, byDegrees degrees: Double,
                       fill: (r: Double, g: Double, b: Double) = (1, 1, 1)) -> CGImage? {
        let t = degrees * .pi / 180
        let w = Double(image.width), h = Double(image.height)
        let nw = Int((abs(w * cos(t)) + abs(h * sin(t))).rounded(.up))
        let nh = Int((abs(w * sin(t)) + abs(h * cos(t))).rounded(.up))
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: nw, height: nh, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(red: fill.r, green: fill.g, blue: fill.b, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: nw, height: nh))
        ctx.interpolationQuality = .high
        // CGContext is y-up, so a positive rotation is counter-clockwise on screen.
        ctx.translateBy(x: CGFloat(nw) / 2, y: CGFloat(nh) / 2)
        ctx.rotate(by: CGFloat(t))
        ctx.draw(image, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
        return ctx.makeImage()
    }

    // MARK: - Helpers

    private struct RGBABuffer {
        let width: Int
        let height: Int
        let pixels: [UInt8]
    }

    /// Draw the image into an RGBA buffer whose long side is ~`workingLongSide`.
    /// Row 0 of the buffer is the top of the image.
    private static func downscaleRGBA(_ image: CGImage) -> RGBABuffer? {
        let longSide = max(image.width, image.height)
        guard longSide > 0 else { return nil }
        let scale = min(1.0, Double(workingLongSide) / Double(longSide))
        let w = max(1, Int((Double(image.width) * scale).rounded()))
        let h = max(1, Int((Double(image.height) * scale).rounded()))
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let ok: Bool = pixels.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? RGBABuffer(width: w, height: h, pixels: pixels) : nil
    }
}
