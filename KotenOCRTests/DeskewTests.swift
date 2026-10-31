import XCTest
import CoreGraphics
@testable import KotenOCR

final class DeskewTests: XCTestCase {

    /// Paper-coloured page with dark "text columns" (or rows) tilted by `degrees`, drawn directly in
    /// pixel space (row 0 = top) so the angle convention is unambiguous:
    /// a vertical column follows x = x0 + y * tan(degrees).
    private func makeLinedImage(degrees: Double, vertical: Bool = true,
                                width: Int = 1200, height: Int = 1600) -> CGImage {
        let t = degrees * .pi / 180
        let c = cos(t), s = sin(t)
        var px = [UInt8](repeating: 0, count: width * height * 4)
        let cx = Double(width) / 2, cy = Double(height) / 2
        let period = 60.0, stroke = 14.0
        for y in 0..<height {
            for x in 0..<width {
                let dx = Double(x) - cx, dy = Double(y) - cy
                // u: across the lines, v: along the lines
                let u = vertical ? dx * c - dy * s : dx * s + dy * c
                let v = vertical ? dx * s + dy * c : dx * c - dy * s
                let inLine = (u + 10_000).truncatingRemainder(dividingBy: period) < stroke
                // break lines into "characters" so it looks like text, not ruled paper
                let inChar = (v + 10_000).truncatingRemainder(dividingBy: 40) < 30
                let inside = abs(dx) < Double(width) * 0.4 && abs(dy) < Double(height) * 0.4
                let ink = inLine && inChar && inside
                let i = (y * width + x) * 4
                px[i] = ink ? 30 : 235
                px[i + 1] = ink ? 30 : 228
                px[i + 2] = ink ? 30 : 215
                px[i + 3] = 255
            }
        }
        let data = Data(px) as CFData
        let provider = CGDataProvider(data: data)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)!
    }

    /// Keystone page: column lean varies linearly across the page from `-edgeDegrees` (left edge of the
    /// text area) to `+edgeDegrees` (right edge), as when a page is photographed from an oblique angle.
    private func makeKeystoneImage(edgeDegrees: Double, width: Int = 1200, height: Int = 1600) -> CGImage {
        var px = [UInt8](repeating: 0, count: width * height * 4)
        let cx = Double(width) / 2, cy = Double(height) / 2
        let half = Double(width) * 0.4
        let period = 60.0, stroke = 14.0
        func lean(_ x0: Double) -> Double { edgeDegrees * (x0 / half) * .pi / 180 }
        for y in 0..<height {
            for x in 0..<width {
                let dx = Double(x) - cx, dy = Double(y) - cy
                // column coordinate x0 such that x = x0 + dy * tan(lean(x0)); fixed-point iteration
                var x0 = dx
                for _ in 0..<4 { x0 = dx - dy * tan(lean(x0)) }
                let inLine = (x0 + 10_000).truncatingRemainder(dividingBy: period) < stroke
                let inChar = (dy + 10_000).truncatingRemainder(dividingBy: 40) < 30
                let inside = abs(dx) < half && abs(dy) < Double(height) * 0.4
                let ink = inLine && inChar && inside
                let i = (y * width + x) * 4
                px[i] = ink ? 30 : 235; px[i + 1] = ink ? 30 : 228; px[i + 2] = ink ? 30 : 215; px[i + 3] = 255
            }
        }
        let provider = CGDataProvider(data: Data(px) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)!
    }

    func testKeystonePageIsNotGloballyRotated() throws {
        let image = makeKeystoneImage(edgeDegrees: 3)
        let est = try XCTUnwrap(Deskew.estimateSkew(image, orientation: .vertical))
        let strips = est.stripAngles.compactMap { $0 }
        XCTAssertEqual(strips.count, 3)
        XCTAssertGreaterThan((strips.max() ?? 0) - (strips.min() ?? 0), Deskew.maxStripSpread,
                             "strips lean in opposite directions: \(est.stripAngles)")
        XCTAssertFalse(est.stripsAgree)
        XCTAssertFalse(est.shouldRotate)
        let out = Deskew.deskew(image, orientation: .vertical)
        XCTAssertEqual(out.angle, 0)
        XCTAssertTrue(out.image === image, "keystone page must be passed through unchanged")
    }

    func testUniformlyRotatedPageStillRotatesAndStripsAgree() throws {
        for angle in [-4.0, 3.0] {
            let image = makeLinedImage(degrees: angle)
            let est = try XCTUnwrap(Deskew.estimateSkew(image, orientation: .vertical))
            for a in est.stripAngles.compactMap({ $0 }) {
                XCTAssertEqual(a, angle, accuracy: 0.4, "strip angle for uniform \(angle)°")
            }
            XCTAssertTrue(est.stripsAgree)
            XCTAssertTrue(est.shouldRotate)
            XCTAssertEqual(Deskew.deskew(image, orientation: .vertical).angle, angle, accuracy: 0.3)
        }
    }

    func testEstimatesKnownAnglesVertical() throws {
        for angle in [-5.0, -2.0, 1.5, 4.0] {
            let est = try XCTUnwrap(Deskew.estimateSkew(makeLinedImage(degrees: angle), orientation: .vertical))
            XCTAssertEqual(est.angle, angle, accuracy: 0.3, "vertical lines tilted \(angle)°")
            XCTAssertTrue(est.shouldRotate, "should rotate at \(angle)°")
        }
    }

    func testEstimatesKnownAngleHorizontalAuto() throws {
        let est = try XCTUnwrap(Deskew.estimateSkew(makeLinedImage(degrees: -3.0, vertical: false), orientation: .auto))
        XCTAssertEqual(est.angle, -3.0, accuracy: 0.3)
    }

    func testStraightImageIsNotRotated() throws {
        let image = makeLinedImage(degrees: 0)
        let est = try XCTUnwrap(Deskew.estimateSkew(image, orientation: .vertical))
        XCTAssertEqual(est.angle, 0, accuracy: 0.3)
        XCTAssertFalse(est.shouldRotate)
        let out = Deskew.deskew(image, orientation: .vertical)
        XCTAssertEqual(out.angle, 0)
        XCTAssertTrue(out.image === image, "a straight page must be passed through unchanged")
    }

    func testDeskewedImageIsStraight() throws {
        // Checks the rotation direction: after correction the estimate must be ~0°.
        for angle in [-4.0, 2.5] {
            let out = Deskew.deskew(makeLinedImage(degrees: angle), orientation: .vertical)
            XCTAssertEqual(out.angle, angle, accuracy: 0.3)
            let after = try XCTUnwrap(Deskew.estimateSkew(out.image, orientation: .vertical))
            XCTAssertEqual(after.angle, 0, accuracy: 0.3, "residual skew after correcting \(angle)°")
            XCTAssertGreaterThan(out.image.width, 1200, "canvas expands so nothing is cut off")
        }
    }

    func testBlankImageIsNotRotated() throws {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 400, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.setFillColor(red: 0.95, green: 0.93, blue: 0.9, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 600))
        let est = try XCTUnwrap(Deskew.estimateSkew(try XCTUnwrap(ctx.makeImage())))
        XCTAssertFalse(est.shouldRotate)
    }

    func testEstimatePerformance() {
        let image = makeLinedImage(degrees: 2, width: 3024, height: 4032)
        measure {
            _ = Deskew.estimateSkew(image, orientation: .vertical)
        }
    }
}
