import UIKit

extension UIImage {
    /// Returns a CGImage with orientation normalized to `.up`.
    /// This ensures EXIF orientation metadata is baked into the pixel data.
    var normalizedCGImage: CGImage? {
        normalizedCGImage(maxLongSide: nil)
    }

    /// Upright CGImage, at most `maxLongSide` pixels on the long side, drawn at that size in one pass
    /// (no full-size upright copy before downscaling) into an 8-bit bitmap.
    /// Returns nil if it cannot be drawn. It used to hand back the un-rotated `cgImage` instead,
    /// whose pixels do not match what the user sees, so every box would land on the wrong text.
    func normalizedCGImage(maxLongSide: Int?) -> CGImage? {
        let pixelW = size.width * scale
        let pixelH = size.height * scale
        guard pixelW >= 1, pixelH >= 1 else { return nil }
        let factor = maxLongSide.map { min(1, CGFloat($0) / max(pixelW, pixelH)) } ?? 1
        if imageOrientation == .up, factor == 1, let cgImage {
            return cgImage
        }

        let target = CGSize(width: max(1, (pixelW * factor).rounded()), height: max(1, (pixelH * factor).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard  // the extended range would double the bitmap
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.cgImage
    }
}

extension CGImage {
    /// Returns a new CGImage rotated 90° clockwise (as displayed on screen).
    func rotated90Clockwise() -> CGImage? {
        let w = width
        let h = height
        // Always draw into 8-bit RGBA. Reusing the image's own colour space and depth failed for
        // 16-bit grayscale scans (and CMYK / indexed images), which cannot back an RGBA context,
        // so the rotate button did nothing.
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: h,
            height: w,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // CG coordinate system has Y pointing up; negate angle for clockwise on screen
        context.translateBy(x: 0, y: CGFloat(w))
        context.rotate(by: -.pi / 2)
        context.draw(self, in: CGRect(x: 0, y: 0, width: w, height: h))
        return context.makeImage()
    }
}
