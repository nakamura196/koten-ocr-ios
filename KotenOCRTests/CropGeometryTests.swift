import XCTest
@testable import KotenOCR

final class CropGeometryTests: XCTestCase {

    private let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)

    func testMoveAppliesCumulativeTranslationToStartRectOnly() {
        let start = CGRect(x: 100, y: 100, width: 100, height: 100)
        // Simulate a drag reported as cumulative translations 10, 20, 30 from the same start.
        var rect = start
        for dx in [10.0, 20.0, 30.0] {
            rect = CropGeometry.moved(start, by: CGSize(width: dx, height: 0), within: bounds)
        }
        XCTAssertEqual(rect.minX, 130, accuracy: 0.001)   // not 100+10+20+30
    }

    func testMoveIsClampedToBounds() {
        let start = CGRect(x: 100, y: 100, width: 100, height: 100)
        let r = CropGeometry.moved(start, by: CGSize(width: 1000, height: -1000), within: bounds)
        XCTAssertEqual(r.maxX, 400, accuracy: 0.001)
        XCTAssertEqual(r.minY, 0, accuracy: 0.001)
        XCTAssertEqual(r.size, start.size)
    }

    func testPixelRectScalesToImage() throws {
        let frame = CGRect(x: 10, y: 20, width: 200, height: 100)
        let crop = CGRect(x: 10, y: 20, width: 100, height: 50)
        let r = try XCTUnwrap(CropGeometry.pixelRect(cropRect: crop, imageFrame: frame, imageSize: CGSize(width: 2000, height: 1000)))
        XCTAssertEqual(r, CGRect(x: 0, y: 0, width: 1000, height: 500))
    }

    func testPixelRectNilWhenEmpty() {
        XCTAssertNil(CropGeometry.pixelRect(cropRect: .zero, imageFrame: .zero, imageSize: CGSize(width: 10, height: 10)))
        XCTAssertNil(CropGeometry.pixelRect(cropRect: CGRect(x: 500, y: 500, width: 10, height: 10),
                                            imageFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
                                            imageSize: CGSize(width: 100, height: 100)))
    }

    /// Skip hands back the displayed (rotated) image, so its dimensions must be swapped.
    func testRotatedImageHasSwappedDimensions() throws {
        let ctx = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let img = try XCTUnwrap(ctx.makeImage())
        let rotated = try XCTUnwrap(img.rotated90Clockwise())
        XCTAssertEqual(rotated.width, 20)
        XCTAssertEqual(rotated.height, 40)
    }
}
