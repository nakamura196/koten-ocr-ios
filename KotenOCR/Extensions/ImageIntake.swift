import CoreGraphics
import ImageIO
import UIKit

/// Brings every image that enters the app (camera, photo library, document scanner, history,
/// test automation) down to at most `maxLongSide` pixels on the long side, with orientation baked in.
///
/// A 48 MP photo (8064×6048) is 186 MB as an RGBA bitmap, and the pipeline keeps several of them
/// (pre-crop image, deskewed copy, display, history encode). Detection runs at 1024 px and line
/// crops are resized to 16–32 px high, so pixels above ~4000 px add memory but no accuracy.
enum ImageIntake {
    static let maxLongSide = 4096

    /// Decodes encoded image data (JPEG/HEIC/PNG) straight to a downscaled, upright CGImage.
    /// ImageIO decodes at the reduced size, so the full-size bitmap is never allocated.
    static func decode(_ data: Data, maxLongSide: Int = maxLongSide) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        return decode(source: source, maxLongSide: maxLongSide)
    }

    static func decode(fileURL: URL, maxLongSide: Int = maxLongSide) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        return decode(source: source, maxLongSide: maxLongSide)
    }

    private static func decode(source: CGImageSource, maxLongSide: Int) -> CGImage? {
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let w = (props?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let h = (props?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        // Never upscale: a small image keeps its own size.
        let target = w > 0 && h > 0 ? min(maxLongSide, max(w, h)) : maxLongSide
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // apply EXIF orientation
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: target
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Downscales an already decoded image if it is larger than `maxLongSide`; otherwise returns it as is.
    static func limit(_ image: CGImage, maxLongSide: Int = maxLongSide) -> CGImage {
        let longSide = max(image.width, image.height)
        guard longSide > maxLongSide, longSide > 0 else { return image }
        let scale = Double(maxLongSide) / Double(longSide)
        let w = max(1, Int((Double(image.width) * scale).rounded()))
        let h = max(1, Int((Double(image.height) * scale).rounded()))
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            return image
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }

    /// Upright, size-limited CGImage from a UIImage (document scanner pages).
    /// Rotation and downscaling happen in one draw; there is no fallback to the un-rotated `cgImage`.
    static func limit(_ image: UIImage, maxLongSide: Int = maxLongSide) -> CGImage? {
        image.normalizedCGImage(maxLongSide: maxLongSide)
    }
}
