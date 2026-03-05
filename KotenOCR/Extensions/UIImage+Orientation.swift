import UIKit

extension UIImage {
    /// Returns a CGImage with orientation normalized to `.up`.
    /// This ensures EXIF orientation metadata is baked into the pixel data.
    var normalizedCGImage: CGImage? {
        if imageOrientation == .up {
            return cgImage
        }

        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return normalized?.cgImage ?? cgImage
    }
}

extension CGImage {
    /// Returns a new CGImage rotated 90° clockwise (as displayed on screen).
    func rotated90Clockwise() -> CGImage? {
        let w = width
        let h = height
        let colorSpace = colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: h,
            height: w,
            bitsPerComponent: bitsPerComponent,
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
