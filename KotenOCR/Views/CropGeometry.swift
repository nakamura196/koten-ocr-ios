import CoreGraphics

/// Pure geometry used by CropView (kept free of UI so it can be unit tested).
enum CropGeometry {

    /// Moves `start` by `translation` (cumulative since the drag began) and keeps it inside `bounds`.
    static func moved(_ start: CGRect, by translation: CGSize, within bounds: CGRect) -> CGRect {
        var r = start.offsetBy(dx: translation.width, dy: translation.height)
        r.origin.x = max(bounds.minX, min(r.origin.x, bounds.maxX - r.width))
        r.origin.y = max(bounds.minY, min(r.origin.y, bounds.maxY - r.height))
        return r
    }

    /// Converts the on-screen crop rect into a pixel rect of the image, clamped to the image.
    /// Returns nil when nothing is left to crop.
    static func pixelRect(cropRect: CGRect, imageFrame: CGRect, imageSize: CGSize) -> CGRect? {
        guard imageFrame.width > 0, imageFrame.height > 0 else { return nil }
        let scaleX = imageSize.width / imageFrame.width
        let scaleY = imageSize.height / imageFrame.height
        let pixel = CGRect(
            x: (cropRect.minX - imageFrame.minX) * scaleX,
            y: (cropRect.minY - imageFrame.minY) * scaleY,
            width: cropRect.width * scaleX,
            height: cropRect.height * scaleY
        ).integral
        let clamped = pixel.intersection(CGRect(origin: .zero, size: imageSize))
        return clamped.isNull || clamped.isEmpty ? nil : clamped
    }
}
