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

    // MARK: - Rotation

    /// 16-bit grayscale is common for archival scans, and ImageIntake keeps it 16-bit. Rotating it
    /// built an RGBA context with the image's gray colour space and depth, which CoreGraphics refuses.
    func testRotateSixteenBitGrayscaleImage() throws {
        let bytesPerRow = 40 * 2
        let pixels = Data(repeating: 0x80, count: bytesPerRow * 20)
        let gray = try XCTUnwrap(CGImage(
            width: 40, height: 20, bitsPerComponent: 16, bitsPerPixel: 16, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue | CGBitmapInfo.byteOrder16Little.rawValue),
            provider: try XCTUnwrap(CGDataProvider(data: pixels as CFData)), decode: nil,
            shouldInterpolate: false, intent: .defaultIntent))
        let rotated = try XCTUnwrap(gray.rotated90Clockwise(), "a 16-bit grayscale image should rotate")
        XCTAssertEqual(rotated.width, 20)
        XCTAssertEqual(rotated.height, 40)
    }

    // MARK: - UIImage orientation

    /// A scanner page stored sideways (orientation .right) comes out upright and already downscaled.
    func testLimitUIImageAppliesOrientationAndSize() throws {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 800, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 400))
        ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 300, width: 100, height: 100))  // stored top-left corner (CG is y-up)
        let stored = try XCTUnwrap(ctx.makeImage())
        let ui = UIImage(cgImage: stored, scale: 1, orientation: .right)

        let upright = try XCTUnwrap(ImageIntake.limit(ui, maxLongSide: 200))
        XCTAssertEqual(upright.width, 100)
        XCTAssertEqual(upright.height, 200)
        // .right shows the stored top-left corner at the top right.
        XCTAssertLessThan(try luminance(upright, x: 95, y: 5), 0.2)
        XCTAssertGreaterThan(try luminance(upright, x: 5, y: 5), 0.8)
    }

    private func luminance(_ image: CGImage, x: Int, y: Int) throws -> Double {
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = try XCTUnwrap(CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // Draw so that pixel (x, y) from the top lands on the single destination pixel.
        ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return Double(px[0]) / 255
    }
}
