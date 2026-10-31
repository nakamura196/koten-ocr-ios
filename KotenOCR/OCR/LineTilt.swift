import CoreGraphics
import Foundation

/// Per-line lean correction for vertical text (古典籍 mode), applied after detection.
///
/// Global `Deskew` fixes a page that is rotated as a whole. A page photographed at an angle
/// (keystone) is different: the columns lean by different amounts across the page, so no single
/// rotation fits. The detector still returns axis-aligned boxes, and the box of a leaning column is
/// wider than the column, so the crop handed to PARSeq contains ink from the neighbouring columns.
///
/// For each tall box this estimates the column's own lean (projection profile of the ink inside the
/// box, ±6°), and when the lean is clear it cuts an oriented crop that follows the column and is
/// only as wide as the column's ink. Boxes that do not lean are cropped exactly as before.
///
/// Angle convention as in `Deskew` (pixels, y down): a positive angle means the column runs from
/// top-left to bottom-right, `x = x0 + y * tan(angle)`.
enum LineTilt {
    static let maxAngle = 6.0
    static let angleStep = 0.25
    /// Leans smaller than this are left alone (the axis-aligned crop is already good).
    static let minAngle = 0.5
    /// Profile score at the best angle divided by the score at 0°; below this the lean is noise.
    static let minGain = 1.03
    /// Only boxes at least this many times taller than wide are treated as vertical lines.
    static let minAspect = 3.0
    static let minHeight = 48
    /// Boxes are analysed at most this many rows high (downscaled), which bounds the cost.
    static let workRows = 256

    struct Plan: Equatable {
        /// Lean in degrees (see convention above).
        let angle: Double
        let gain: Double
        /// Centre of the oriented crop, in image pixels.
        let center: CGPoint
        /// Size of the oriented crop: across the column, and along it.
        let width: Double
        let height: Double
    }

    // MARK: - Public API

    /// The image PARSeq should read for `box`: an oriented crop when the column clearly leans,
    /// otherwise exactly `image.cropping(to:)` of the box as before.
    static func crop(_ image: CGImage, box: [Int]) -> (image: CGImage?, plan: Plan?) {
        guard box.count >= 4 else { return (nil, nil) }
        let rect = CGRect(x: max(0, box[0]), y: max(0, box[1]),
                          width: max(1, box[2] - box[0]), height: max(1, box[3] - box[1]))
        guard let plain = image.cropping(to: rect) else { return (nil, nil) }
        guard let region = Region(plain, origin: rect.origin),
              let plan = plan(region: region) else {
            return (plain, nil)
        }
        return (orientedCrop(region: region, plan: plan) ?? plain, plan)
    }

    /// Lean estimate for one detection box (nil when the box is not a tall line, or does not lean).
    static func plan(_ image: CGImage, box: [Int]) -> Plan? {
        guard box.count >= 4 else { return nil }
        let rect = CGRect(x: max(0, box[0]), y: max(0, box[1]),
                          width: max(1, box[2] - box[0]), height: max(1, box[3] - box[1]))
        guard let plain = image.cropping(to: rect), let region = Region(plain, origin: rect.origin) else { return nil }
        return plan(region: region)
    }

    // MARK: - Pixels of one box

    /// RGBA (premultiplied, opaque) pixels of the box, row 0 = top.
    struct Region {
        let pixels: [UInt8]
        let width: Int
        let height: Int
        /// Position of the region's top-left pixel in the full image.
        let origin: CGPoint

        init?(_ image: CGImage, origin: CGPoint) {
            let w = image.width, h = image.height
            guard w > 0, h > 0 else { return nil }
            var px = [UInt8](repeating: 0, count: w * h * 4)
            let ok = px.withUnsafeMutableBytes { buf -> Bool in
                guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard ok else { return nil }
            pixels = px; width = w; height = h; self.origin = origin
        }
    }

    // MARK: - Lean estimation

    static func plan(region: Region) -> Plan? {
        let w = region.width, h = region.height
        guard Double(h) >= minAspect * Double(w), h >= minHeight, w >= 6 else { return nil }

        // Downscaled grey image of the box (area average).
        let s = min(1.0, Double(workRows) / Double(h))
        let rw = max(4, Int((Double(w) * s).rounded()))
        let rh = max(4, Int((Double(h) * s).rounded()))
        var grey = [Float](repeating: 0, count: rw * rh)
        for ty in 0..<rh {
            let y0 = ty * h / rh, y1 = max(y0 + 1, (ty + 1) * h / rh)
            for tx in 0..<rw {
                let x0 = tx * w / rw, x1 = max(x0 + 1, (tx + 1) * w / rw)
                var sum: Float = 0
                for y in y0..<y1 {
                    var i = (y * w + x0) * 4
                    for _ in x0..<x1 {
                        sum += 0.299 * Float(region.pixels[i]) + 0.587 * Float(region.pixels[i + 1]) + 0.114 * Float(region.pixels[i + 2])
                        i += 4
                    }
                }
                grey[ty * rw + tx] = sum / Float((y1 - y0) * (x1 - x0))
            }
        }

        // Ink: clearly darker than the paper level (75th percentile of the box).
        var hist = [Int](repeating: 0, count: 256)
        for g in grey { hist[min(255, max(0, Int(g)))] += 1 }
        var acc = 0, paper = 255
        for v in 0..<256 { acc += hist[v]; if acc * 4 >= grey.count * 3 { paper = v; break } }
        let threshold = Float(paper) * 0.78
        var xs: [Double] = [], ys: [Double] = []
        for y in 0..<rh {
            for x in 0..<rw where grey[y * rw + x] < threshold {
                xs.append(Double(x) - Double(rw) / 2)
                ys.append(Double(y) - Double(rh) / 2)
            }
        }
        guard xs.count >= 30 else { return nil }

        // Projection profile across the column for each candidate lean; keep the sharpest.
        let nb = rw + 2 * Int(Double(rh) * tan((maxAngle + 0.5) * .pi / 180)) + 4
        let off = Double(nb) / 2
        var best: (angle: Double, score: Double, hist: [Double]) = (0, -1, [])
        var score0 = 0.0
        let steps = Int((maxAngle / angleStep).rounded())
        for k in -steps...steps {
            let a = Double(k) * angleStep
            let t = tan(a * .pi / 180)
            var bins = [Double](repeating: 0, count: nb)
            for i in 0..<xs.count {
                let u = Int((xs[i] - ys[i] * t + off).rounded(.down))
                if u >= 0 && u < nb { bins[u] += 1 }
            }
            var sc = 0.0
            for b in bins { sc += b * b }
            if k == 0 { score0 = sc }
            if sc > best.score { best = (a, sc, bins) }
        }
        guard score0 > 0 else { return nil }
        let gain = best.score / score0
        guard abs(best.angle) >= minAngle, gain >= minGain else { return nil }

        // Ink extent of the column through the box centre, along the line's normal.
        let p = smooth3(best.hist)
        let c = Int(off.rounded())
        let win = max(2, Int(Double(rw) * 0.3))
        let lo = max(0, c - win), hi = min(p.count - 1, c + win)
        guard lo <= hi else { return nil }
        var pk = lo
        for i in lo...hi where p[i] > p[pk] { pk = i }
        let thr = p[pk] * 0.12
        var l = pk, r = pk
        while l > 0 && p[l - 1] > thr { l -= 1 }
        while r < p.count - 1 && p[r + 1] > thr { r += 1 }
        let centreOffset = ((Double(l + r + 1) / 2) - off) / s   // horizontal, at mid-height, original px
        var width = Double(r - l + 1) / s

        let t = best.angle * .pi / 180
        let expected = Double(w) - Double(h) * abs(tan(t))      // a column that exactly fits the box
        width = min(max(width, 0.6 * expected) * 1.12 + 4, Double(w)) * cos(t)

        let cx = region.origin.x + Double(w) / 2 + centreOffset
        let cy = region.origin.y + Double(h) / 2
        return Plan(angle: best.angle, gain: gain, center: CGPoint(x: cx, y: cy),
                    width: width, height: Double(h) / cos(t))
    }

    private static func smooth3(_ v: [Double]) -> [Double] {
        guard v.count > 2 else { return v }
        var out = v
        for i in 0..<v.count {
            let a = i > 0 ? v[i - 1] : 0, b = i < v.count - 1 ? v[i + 1] : 0
            out[i] = (a + v[i] + b) / 3
        }
        return out
    }

    // MARK: - Oriented crop

    /// Bilinear resampling of the rectangle described by `plan` so that the column becomes upright.
    static func orientedCrop(region: Region, plan: Plan) -> CGImage? {
        let W = max(1, Int(plan.width.rounded())), H = max(1, Int(plan.height.rounded()))
        let t = plan.angle * .pi / 180
        let c = cos(t), s = sin(t)
        // Output pixel (i, j) -> source: centre + (i - W/2) * n + (j - H/2) * d,
        // with d = (sin, cos) along the column and n = (cos, -sin) across it.
        let cx = Double(plan.center.x - region.origin.x), cy = Double(plan.center.y - region.origin.y)
        let bx = cx - c * Double(W) / 2 - s * Double(H) / 2
        let by = cy + s * Double(W) / 2 - c * Double(H) / 2
        let sw = region.width, sh = region.height
        var out = [UInt8](repeating: 255, count: W * H * 4)
        region.pixels.withUnsafeBufferPointer { src in
            for j in 0..<H {
                for i in 0..<W {
                    let x = min(max(c * Double(i) + s * Double(j) + bx, 0), Double(sw - 1))
                    let y = min(max(-s * Double(i) + c * Double(j) + by, 0), Double(sh - 1))
                    let x0 = Int(x), y0 = Int(y)
                    let x1 = min(x0 + 1, sw - 1), y1 = min(y0 + 1, sh - 1)
                    let fx = x - Double(x0), fy = y - Double(y0)
                    let o = (j * W + i) * 4
                    for ch in 0..<3 {
                        let v00 = Double(src[(y0 * sw + x0) * 4 + ch]), v10 = Double(src[(y0 * sw + x1) * 4 + ch])
                        let v01 = Double(src[(y1 * sw + x0) * 4 + ch]), v11 = Double(src[(y1 * sw + x1) * 4 + ch])
                        let v = (v00 * (1 - fx) + v10 * fx) * (1 - fy) + (v01 * (1 - fx) + v11 * fx) * fy
                        out[o + ch] = UInt8(max(0, min(255, v.rounded())))
                    }
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(out) as CFData) else { return nil }
        return CGImage(width: W, height: H, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: W * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    // MARK: - Result clean-up

    /// Glyphs the recogniser emits when it cannot read anything (□ 〓 and U+FFFD).
    static let placeholderGlyphs: Set<Character> = ["□", "〓", "\u{FFFD}"]

    static func placeholderCount(_ text: String) -> Int {
        text.reduce(0) { $0 + (placeholderGlyphs.contains($1) ? 1 : 0) }
    }

    /// True for a recognised line made only of placeholder glyphs, e.g. "□□□□□□□□" read from a stamp
    /// or label. Such lines are dropped from the result.
    static func isPlaceholderOnly(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { placeholderGlyphs.contains($0) }
    }

    /// Drop a line when its box lies mostly inside another line's box and its text is mostly a
    /// substring of that line's text: the detector found the same column twice (a whole column plus
    /// a piece of it), which otherwise shows up as a line repeating its neighbour's text.
    static func dropSameLineDuplicates(_ detections: [Detection],
                                       minOverlap: Double = 0.6, minSimilarity: Double = 0.6) -> [Detection] {
        func area(_ b: [Int]) -> Int { b.count >= 4 ? (b[2] - b[0]) * (b[3] - b[1]) : 0 }
        let order = detections.indices.sorted { area(detections[$0].box) > area(detections[$1].box) }
        var keep = [Bool](repeating: true, count: detections.count)
        for (n, i) in order.enumerated() where keep[i] {
            let a = detections[i].box
            guard a.count >= 4 else { continue }
            for j in order[(n + 1)...] where keep[j] {
                let b = detections[j].box
                guard b.count >= 4 else { continue }
                let ox = min(a[2], b[2]) - max(a[0], b[0]), oy = min(a[3], b[3]) - max(a[1], b[1])
                guard ox > 0, oy > 0,
                      Double(ox) >= minOverlap * Double(b[2] - b[0]),
                      Double(oy) >= minOverlap * Double(b[3] - b[1]) else { continue }
                if substringSimilarity(detections[j].text, in: detections[i].text) >= minSimilarity {
                    keep[j] = false
                }
            }
        }
        return detections.indices.filter { keep[$0] }.map { detections[$0] }
    }

    /// 1 − (edit distance between `small` and its best-matching substring of `large`) / len(small).
    static func substringSimilarity(_ small: String, in large: String) -> Double {
        let a = Array(small), b = Array(large)
        guard !a.isEmpty else { return 0 }
        var prev = [Int](repeating: 0, count: b.count + 1)   // a match may start anywhere in `large`
        for i in 1...a.count {
            var cur = [Int](repeating: 0, count: b.count + 1)
            cur[0] = i
            if !b.isEmpty {
                for j in 1...b.count {
                    cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                }
            }
            prev = cur
        }
        return 1 - Double(prev.min() ?? a.count) / Double(a.count)
    }
}
