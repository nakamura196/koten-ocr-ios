import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import KotenOCR

final class ImageIntakeTests: XCTestCase {

    private func solidImage(width: Int, height: Int) throws -> CGImage {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.setFillColor(red: 0.9, green: 0.85, blue: 0.7, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(ctx.makeImage())
    }

    private func jpeg(_ image: CGImage, orientation: Int) throws -> Data {
        let data = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, [kCGImagePropertyOrientation: orientation,
                                                 kCGImageDestinationLossyCompressionQuality: 0.5] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return data as Data
    }

    /// A 48 MP camera JPEG stored landscape with EXIF "rotate 90°" (how the camera saves a portrait shot)
    /// comes out upright and at most 4096 px on the long side.
    func testDecodeDownscalesAndAppliesOrientation() throws {
        let data = try jpeg(solidImage(width: 8064, height: 6048), orientation: 6)
        let img = try XCTUnwrap(ImageIntake.decode(data))
        XCTAssertEqual(max(img.width, img.height), ImageIntake.maxLongSide)
        XCTAssertLessThan(img.width, img.height, "EXIF orientation should be applied (portrait)")
    }

    func testDecodeKeepsSmallImageSize() throws {
        let data = try jpeg(solidImage(width: 1200, height: 900), orientation: 1)
        let img = try XCTUnwrap(ImageIntake.decode(data))
        XCTAssertEqual(img.width, 1200)
        XCTAssertEqual(img.height, 900)
    }

    func testLimitDownscalesLargeBitmapOnly() throws {
        let big = try solidImage(width: 6048, height: 8064)
        let limited = ImageIntake.limit(big)
        XCTAssertEqual(limited.height, 4096)
        XCTAssertEqual(limited.width, 3072)

        let small = try solidImage(width: 3024, height: 4032)
        XCTAssertTrue(ImageIntake.limit(small) === small, "images within the limit are passed through")
    }
}
