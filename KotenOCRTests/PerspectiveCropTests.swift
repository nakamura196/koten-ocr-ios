import XCTest
import CoreGraphics
@testable import KotenOCR

final class PerspectiveCropTests: XCTestCase {

    func testCornerOrderIsNormalised() {
        let shuffled = [CGPoint(x: 90, y: 80), CGPoint(x: 10, y: 20), CGPoint(x: 15, y: 90), CGPoint(x: 95, y: 10)]
        let q = Quad(normalizing: shuffled)!
        XCTAssertEqual(q.topLeft, CGPoint(x: 10, y: 20))
        XCTAssertEqual(q.topRight, CGPoint(x: 95, y: 10))
        XCTAssertEqual(q.bottomRight, CGPoint(x: 90, y: 80))
        XCTAssertEqual(q.bottomLeft, CGPoint(x: 15, y: 90))
        XCTAssertNil(Quad(normalizing: Array(shuffled.prefix(3))))
    }

    func testConvexity() {
        XCTAssertTrue(Quad(rect: CGRect(x: 0, y: 0, width: 10, height: 10)).isConvex)
        let bowtie = Quad(topLeft: CGPoint(x: 0, y: 0), topRight: CGPoint(x: 10, y: 10),
                          bottomRight: CGPoint(x: 10, y: 0), bottomLeft: CGPoint(x: 0, y: 10))
        XCTAssertFalse(bowtie.isConvex)
    }

    func testRectifiedSizeUsesLongerEdges() {
        let q = Quad(topLeft: CGPoint(x: 50, y: 40), topRight: CGPoint(x: 250, y: 20),
                     bottomRight: CGPoint(x: 280, y: 180), bottomLeft: CGPoint(x: 30, y: 170))
        XCTAssertEqual(q.rectifiedSize.width, 250, accuracy: 1)   // bottom edge is longer
        XCTAssertGreaterThan(q.rectifiedSize.height, 130)
    }

    /// Dark trapezoid on white, rectified: the result should be roughly the quad's size and mostly dark.
    func testRectifyProducesExpectedSizeAndContent() throws {
        let w = 400, h = 300
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        // Pixel quad (top-left origin): TL(100,60) TR(300,40) BR(340,240) BL(70,220)
        let q = Quad(topLeft: CGPoint(x: 100, y: 60), topRight: CGPoint(x: 300, y: 40),
                     bottomRight: CGPoint(x: 340, y: 240), bottomLeft: CGPoint(x: 70, y: 220))
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.beginPath()
        // CGContext origin is bottom-left; flip y when drawing
        let pts = q.points.map { CGPoint(x: $0.x, y: CGFloat(h) - $0.y) }
        ctx.move(to: pts[0]); pts.dropFirst().forEach { ctx.addLine(to: $0) }; ctx.closePath(); ctx.fillPath()
        let image = ctx.makeImage()!

        let out = try XCTUnwrap(PerspectiveCrop.rectify(image, pixelQuad: q))
        let expected = q.rectifiedSize
        let outAspect = Double(out.width) / Double(out.height)
        XCTAssertEqual(outAspect, Double(expected.width / expected.height), accuracy: 0.25)
        XCTAssertEqual(Double(out.width), Double(expected.width), accuracy: Double(expected.width) * 0.2)

        // Centre pixel of the result must come from the dark region.
        let data = try XCTUnwrap(out.dataProvider?.data as Data?)
        let bpp = out.bitsPerPixel / 8
        let cx = out.width / 2, cy = out.height / 2
        XCTAssertLessThan(Int(data[cy * out.bytesPerRow + cx * bpp]), 60)
    }

    func testNonConvexQuadIsRejected() {
        let ctx = CGContext(data: nil, width: 50, height: 50, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let bowtie = Quad(topLeft: CGPoint(x: 0, y: 0), topRight: CGPoint(x: 40, y: 40),
                          bottomRight: CGPoint(x: 40, y: 0), bottomLeft: CGPoint(x: 0, y: 40))
        XCTAssertNil(PerspectiveCrop.rectify(ctx.makeImage()!, pixelQuad: bowtie))
    }

    func testNormalizedQuadScalesToPixels() {
        let q = Quad(rect: CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.5)).scaled(to: CGSize(width: 200, height: 100))
        XCTAssertEqual(q.topLeft, CGPoint(x: 50, y: 50))
        XCTAssertEqual(q.bottomRight, CGPoint(x: 150, y: 100))
    }
}
