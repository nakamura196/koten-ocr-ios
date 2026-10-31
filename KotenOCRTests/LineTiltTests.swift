import XCTest
import CoreGraphics
import CoreImage
import ImageIO
import OnnxRuntimeBindings
@testable import KotenOCR

final class LineTiltTests: XCTestCase {

    // MARK: - Synthetic columns (no models needed)

    /// Paper page with dark vertical "columns" leaning by `degrees` (x = x0 + y * tan), drawn in pixel
    /// space (row 0 = top). Columns are `pitch` apart and `stroke` wide, broken into "characters".
    private func makeColumns(degrees: Double, width: Int = 600, height: Int = 900,
                             pitch: Double = 60, stroke: Double = 26) -> CGImage {
        let t = tan(degrees * .pi / 180)
        var px = [UInt8](repeating: 0, count: width * height * 4)
        let cy = Double(height) / 2
        for y in 0..<height {
            for x in 0..<width {
                let u = Double(x) - (Double(y) - cy) * t
                let inLine = (u + 6_000).truncatingRemainder(dividingBy: pitch) < stroke
                let inChar = Double(y).truncatingRemainder(dividingBy: 40) < 30
                let inside = y > 40 && y < height - 40
                let ink = inLine && inChar && inside
                let i = (y * width + x) * 4
                px[i] = ink ? 30 : 235; px[i + 1] = ink ? 30 : 228; px[i + 2] = ink ? 30 : 215; px[i + 3] = 255
            }
        }
        let provider = CGDataProvider(data: Data(px) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    /// Axis-aligned box around the column whose centre line passes x = `x0` at mid-height, as the
    /// detector would return it (it covers the whole leaning column).
    private func boxAround(x0: Double, degrees: Double, stroke: Double = 26, height: Int = 900) -> [Int] {
        let half = (Double(height) / 2 - 40) * abs(tan(degrees * .pi / 180))
        return [Int(x0 - half - 2), 40, Int(x0 + stroke + half + 2), height - 40]
    }

    func testEstimatesColumnLean() throws {
        for angle in [-3.0, -1.5, 2.0, 4.0] {
            let image = makeColumns(degrees: angle)
            let plan = try XCTUnwrap(LineTilt.plan(image, box: boxAround(x0: 300, degrees: angle)), "lean \(angle)°")
            XCTAssertEqual(plan.angle, angle, accuracy: 0.3, "lean \(angle)°")
            // The oriented crop is only as wide as the column (26 px), not the whole box.
            XCTAssertLessThan(plan.width, 26 * 1.8, "lean \(angle)°")
            XCTAssertEqual(Double(plan.center.x), 313, accuracy: 3, "centre of the column at mid-height")
        }
    }

    func testStraightColumnIsCroppedAsBefore() throws {
        let image = makeColumns(degrees: 0)
        let box = boxAround(x0: 300, degrees: 0)
        XCTAssertNil(LineTilt.plan(image, box: box))
        let out = LineTilt.crop(image, box: box)
        XCTAssertNil(out.plan)
        let crop = try XCTUnwrap(out.image)
        XCTAssertEqual(crop.width, box[2] - box[0])
        XCTAssertEqual(crop.height, box[3] - box[1])
        // Smaller than minAngle: also left alone.
        XCTAssertNil(LineTilt.plan(makeColumns(degrees: 0.25), box: boxAround(x0: 300, degrees: 0.25)))
    }

    func testShortOrWideBoxesAreNotTilted() {
        let image = makeColumns(degrees: 3)
        XCTAssertNil(LineTilt.plan(image, box: [200, 100, 400, 300]), "not a tall line")
        XCTAssertNil(LineTilt.plan(image, box: [280, 100, 340, 140]), "too short")
    }

    func testOrientedCropIsUpright() throws {
        let image = makeColumns(degrees: 3)
        let out = LineTilt.crop(image, box: boxAround(x0: 300, degrees: 3))
        XCTAssertNotNil(out.plan)
        let crop = try XCTUnwrap(out.image)
        XCTAssertGreaterThan(crop.height, crop.width * 5)
        // Re-estimating on the oriented crop finds no remaining lean.
        XCTAssertNil(LineTilt.plan(crop, box: [0, 0, crop.width, crop.height]))
    }

    // MARK: - Result clean-up

    func testPlaceholderOnlyLines() {
        XCTAssertTrue(LineTilt.isPlaceholderOnly("□□□□□□□□"))
        XCTAssertTrue(LineTilt.isPlaceholderOnly("〓"))
        XCTAssertTrue(LineTilt.isPlaceholderOnly("□\u{FFFD}□"))
        XCTAssertFalse(LineTilt.isPlaceholderOnly(""))
        XCTAssertFalse(LineTilt.isPlaceholderOnly("□□三世□□"))
        XCTAssertFalse(LineTilt.isPlaceholderOnly("いつれの御時にか"))
    }

    func testDropsSameLineDuplicates() {
        let whole = Detection(box: [970, 100, 1060, 720], score: 0.9, classId: 0, className: "text",
                              text: "一下平安海内無事者上自王公下至士")
        let piece = Detection(box: [995, 210, 1060, 720], score: 0.8, classId: 0, className: "text",
                              text: "海内無事者上自王公下至士")
        let neighbour = Detection(box: [890, 110, 956, 725], score: 0.9, classId: 0, className: "text",
                                  text: "琉球功立太主之興基日未鮮有平")
        // An interlinear note inside a column box, with different text, is kept.
        let note = Detection(box: [1000, 600, 1030, 700], score: 0.5, classId: 0, className: "text",
                             text: "なとりなん")
        let out = LineTilt.dropSameLineDuplicates([piece, whole, neighbour, note])
        XCTAssertEqual(out.map(\.text), [whole.text, neighbour.text, note.text])
        XCTAssertEqual(LineTilt.dropSameLineDuplicates([whole, neighbour]).count, 2)
    }

    func testSubstringSimilarity() {
        XCTAssertEqual(LineTilt.substringSimilarity("海内無事", in: "一下平安海内無事者"), 1, accuracy: 1e-9)
        XCTAssertEqual(LineTilt.substringSimilarity("海内有事", in: "一下平安海内無事者"), 0.75, accuracy: 1e-9)
        XCTAssertEqual(LineTilt.substringSimilarity("", in: "abc"), 0)
    }

    // MARK: - Real models on the sample page

    private var detector: RTMDetector!
    private var recognizer: PARSEQRecognizer!
    private var env: ORTEnv!

    private func loadModels() throws {
        guard let det = Bundle.main.path(forResource: "rtmdet-s-1280x1280", ofType: "onnx", inDirectory: "Models"),
              let rec = Bundle.main.path(forResource: "parseq-ndl-32x384-tiny-10", ofType: "onnx", inDirectory: "Models"),
              let chars = Bundle.main.path(forResource: "NDLmoji", ofType: "yaml", inDirectory: "Models") else {
            throw XCTSkip("Koten models not in the app bundle")
        }
        env = try ORTEnv(loggingLevel: .warning)
        detector = try RTMDetector(env: env, modelPath: det)
        recognizer = try PARSEQRecognizer(env: env, modelPath: rec, charListPath: chars)
    }

    private func loadImage(_ path: String) throws -> CGImage {
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
    }

    private func samplePage() throws -> CGImage {
        let path = try XCTUnwrap(Bundle(for: Self.self).path(forResource: "koten_page", ofType: "jpg"))
        return try loadImage(path)
    }

    /// Keystone: the top edge pulled in so the left edge leans −deg and the right edge +deg.
    private func keystone(_ image: CGImage, degrees: Double) throws -> CGImage {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let d = h * CGFloat(tan(degrees * .pi / 180))
        let ci = CIImage(cgImage: image)
        let f = try XCTUnwrap(CIFilter(name: "CIPerspectiveTransform"))
        f.setValue(ci, forKey: kCIInputImageKey)
        // Core Image coordinates: origin at the bottom-left.
        f.setValue(CIVector(x: d, y: h), forKey: "inputTopLeft")
        f.setValue(CIVector(x: w - d, y: h), forKey: "inputTopRight")
        f.setValue(CIVector(x: w, y: 0), forKey: "inputBottomRight")
        f.setValue(CIVector(x: 0, y: 0), forKey: "inputBottomLeft")
        let warped = try XCTUnwrap(f.outputImage)
        let paper = CIImage(color: CIColor(red: 0.88, green: 0.84, blue: 0.76)).cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
        let out = warped.composited(over: paper).cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
        return try XCTUnwrap(CIContext().createCGImage(out, from: CGRect(x: 0, y: 0, width: w, height: h)))
    }

    private func ocr(_ image: CGImage, lineTilt: Bool) async throws -> [Detection] {
        let dets = try detector.detect(image: image)
        return try await OCREngine.recognizeKotenLines(image: image, detections: dets,
                                                       recognizer: recognizer, lineTilt: lineTilt)
    }

    private func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        for i in 1...a.count {
            var cur = [i] + [Int](repeating: 0, count: b.count)
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[b.count]
    }

    /// Character error of each reference line against its best-matching hypothesis line.
    private func lineCER(reference: [String], hypothesis: [String]) -> Double {
        let ref = reference.filter { !$0.isEmpty }
        let errors = ref.map { r in hypothesis.map { levenshtein($0, r) }.min() ?? r.count }.reduce(0, +)
        return Double(errors) / Double(max(1, ref.map(\.count).reduce(0, +)))
    }

    private func repeatsNeighbour(_ dets: [Detection], run: Int = 4) -> Int {
        let sorted = dets.sorted { ($0.box[0] + $0.box[2]) > ($1.box[0] + $1.box[2]) }
        var n = 0
        for (a, b) in zip(sorted, sorted.dropFirst()) {
            let x = Array(a.text), y = Array(b.text)
            var best = 0
            var dp = [Int](repeating: 0, count: y.count + 1)
            for i in 0..<x.count {
                var next = [Int](repeating: 0, count: y.count + 1)
                for j in 0..<y.count where x[i] == y[j] { next[j + 1] = dp[j] + 1; best = max(best, next[j + 1]) }
                dp = next
            }
            if best >= run { n += 1 }
        }
        return n
    }

    /// The ten main columns of the sample page (源氏物語 桐壺 opening), transcribed by hand. The straight
    /// page's own OCR is not used as the reference because it contains duplicate detections.
    private let sampleText = [
        "いつれの御時にか女御更衣あまたさふらひ給ける",
        "中にいとやんことなきゝはにはあらぬかすくれてと",
        "きめき給ふありけりはしめより我はと思ひ",
        "あかり給へる御かた〳〵めさましきものにをとし",
        "めそねみ給おなしほとそれより下らうの更衣たち",
        "はましてやすからす朝夕の宮つかへにつけても",
        "人の心をうこかしうらみをおふつもりにやあり",
        "けむいとあつしくなり行もの心ほそけにさとかち",
        "なるをいよ〳〵あかす哀なる物におもほして",
        "人のそしりをもえはゝからせ給はす世のためし",
    ]

    func testKeystonePageMatchesStraightPage() async throws {
        try loadModels()
        let straight = try samplePage()
        let straightLines = try await ocr(straight, lineTilt: true)
        let cerStraight = lineCER(reference: sampleText, hypothesis: straightLines.map(\.text))
        print(String(format: "[LineTilt] straight page: line CER %.3f, %d lines", cerStraight, straightLines.count))

        for degrees in [2.0, 3.0] {
            let warped = try keystone(straight, degrees: degrees)
            let before = try await ocr(warped, lineTilt: false)
            let after = try await ocr(warped, lineTilt: true)
            let cerBefore = lineCER(reference: sampleText, hypothesis: before.map(\.text))
            let cerAfter = lineCER(reference: sampleText, hypothesis: after.map(\.text))
            print(String(format: "[LineTilt] keystone ±%.0f°: line CER %.3f (no tilt) -> %.3f (tilt); lines %d -> %d; tilted %d",
                         degrees, cerBefore, cerAfter, before.count, after.count,
                         after.filter { LineTilt.plan(warped, box: $0.box) != nil }.count))
            // Tolerance: within 5 points of the straight page's own accuracy.
            XCTAssertLessThanOrEqual(cerAfter, cerStraight + 0.05, "keystone ±\(degrees)°")
            XCTAssertLessThanOrEqual(cerAfter, cerBefore + 0.02, "line tilt must not make it worse")
            XCTAssertEqual(repeatsNeighbour(after), 0, "no line repeats its neighbour's text")
        }
    }

    func testStraightPageIsBarelyTouched() async throws {
        try loadModels()
        let straight = try samplePage()
        let dets = try detector.detect(image: straight)
        let tilted = dets.filter { LineTilt.plan(straight, box: $0.box) != nil }
        // Handwritten columns lean a little on their own; most of them must be read exactly as before.
        XCTAssertLessThanOrEqual(Double(tilted.count), Double(dets.count) * 0.25)
        let plain = try await ocr(straight, lineTilt: false)
        let withTilt = try await ocr(straight, lineTilt: true)
        let cer = lineCER(reference: plain.map(\.text), hypothesis: withTilt.map(\.text))
        print(String(format: "[LineTilt] straight page: %d of %d boxes tilted, CER vs untilted %.3f", tilted.count, dets.count, cer))
        XCTAssertLessThanOrEqual(cer, 0.05)
    }

    /// Optional check on a real photo that is not in the repository (museum material).
    /// Run with: TEST_RUNNER_KOTENOCR_LINETILT_IMAGE=/path/to/page.png xcodebuild test ...
    func testExternalLeaningPhoto() async throws {
        guard let path = ProcessInfo.processInfo.environment["KOTENOCR_LINETILT_IMAGE"], !path.isEmpty else {
            throw XCTSkip("KOTENOCR_LINETILT_IMAGE not set")
        }
        try loadModels()
        let image = try loadImage(path)
        let before = try await ocr(image, lineTilt: false)
        let after = try await ocr(image, lineTilt: true)
        let squares = { (d: [Detection]) in d.map { $0.text.filter { $0 == "□" }.count }.reduce(0, +) }
        print("[LineTilt] external photo: lines \(before.count) -> \(after.count), neighbour repeats \(repeatsNeighbour(before)) -> \(repeatsNeighbour(after)), □ \(squares(before)) -> \(squares(after))")
        for d in before.sorted(by: { $0.box[0] > $1.box[0] }) { print("  before \(d.box) \(d.text)") }
        for d in after.sorted(by: { $0.box[0] > $1.box[0] }) { print("  after  \(d.box) \(d.text)") }
        XCTAssertEqual(repeatsNeighbour(after), 0)
        XCTAssertLessThanOrEqual(squares(after), squares(before))
    }
}
