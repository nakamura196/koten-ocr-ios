import CoreGraphics

/// Pure geometry for the "Edit boxes" mode. All rectangles are in image pixels.
/// Kept free of UI so it can be unit tested (like CropGeometry).
enum BoxEditGeometry {

    /// Smallest side of a box, in image pixels.
    static let minSide: CGFloat = 12

    enum Corner: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    static func imageBounds(_ size: CGSize) -> CGRect {
        CGRect(origin: .zero, size: size)
    }

    /// Moves `start` by the cumulative `translation` since the drag began, keeping it inside `bounds`.
    static func moved(_ start: CGRect, by translation: CGSize, within bounds: CGRect) -> CGRect {
        CropGeometry.moved(start, by: translation, within: bounds)
    }

    /// Drags one corner of `start` by the cumulative `translation`. The opposite corner stays fixed,
    /// the dragged corner is kept inside `bounds`, and the box never gets smaller than `minSide`.
    static func resized(_ start: CGRect, corner: Corner, by translation: CGSize,
                        within bounds: CGRect, minSide: CGFloat = BoxEditGeometry.minSide) -> CGRect {
        var minX = start.minX, maxX = start.maxX, minY = start.minY, maxY = start.maxY
        switch corner {
        case .topLeft, .bottomLeft:
            minX = min(max(start.minX + translation.width, bounds.minX), start.maxX - minSide)
        case .topRight, .bottomRight:
            maxX = max(min(start.maxX + translation.width, bounds.maxX), start.minX + minSide)
        }
        switch corner {
        case .topLeft, .topRight:
            minY = min(max(start.minY + translation.height, bounds.minY), start.maxY - minSide)
        case .bottomLeft, .bottomRight:
            maxY = max(min(start.maxY + translation.height, bounds.maxY), start.minY + minSide)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The rectangle drawn by dragging from `a` to `b`, clamped to `bounds`.
    /// Returns nil when it is smaller than `minSide` on either side.
    static func drawn(from a: CGPoint, to b: CGPoint, within bounds: CGRect,
                      minSide: CGFloat = BoxEditGeometry.minSide) -> CGRect? {
        let r = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
            .intersection(bounds)
        guard !r.isNull, r.width >= minSide, r.height >= minSide else { return nil }
        return r
    }

    /// Splits `rect` in two at `point`. A tall box (vertical text) is cut across the column
    /// (top and bottom pieces); a wide box is cut down the middle (left and right pieces).
    /// Returns nil if the point is outside or either piece would be smaller than `minSide`.
    static func split(_ rect: CGRect, at point: CGPoint,
                      minSide: CGFloat = BoxEditGeometry.minSide) -> (CGRect, CGRect)? {
        guard rect.contains(point) else { return nil }
        if rect.height >= rect.width {
            let cut = point.y
            guard cut - rect.minY >= minSide, rect.maxY - cut >= minSide else { return nil }
            return (CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: cut - rect.minY),
                    CGRect(x: rect.minX, y: cut, width: rect.width, height: rect.maxY - cut))
        } else {
            let cut = point.x
            guard cut - rect.minX >= minSide, rect.maxX - cut >= minSide else { return nil }
            return (CGRect(x: rect.minX, y: rect.minY, width: cut - rect.minX, height: rect.height),
                    CGRect(x: cut, y: rect.minY, width: rect.maxX - cut, height: rect.height))
        }
    }

    static func merged(_ a: CGRect, _ b: CGRect) -> CGRect { a.union(b) }

    /// Index of the box under `point` (the smallest one if several overlap), or nil.
    static func hitBox(at point: CGPoint, in rects: [CGRect]) -> Int? {
        rects.enumerated()
            .filter { $0.element.contains(point) }
            .min { $0.element.width * $0.element.height < $1.element.width * $1.element.height }?
            .offset
    }

    static func point(of corner: Corner, in rect: CGRect) -> CGPoint {
        switch corner {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    /// The corner of `rect` nearest to `point` that lies within `radius`, or nil.
    static func hitCorner(at point: CGPoint, of rect: CGRect, radius: CGFloat) -> Corner? {
        Corner.allCases
            .map { ($0, hypot(self.point(of: $0, in: rect).x - point.x, self.point(of: $0, in: rect).y - point.y)) }
            .filter { $0.1 <= radius }
            .min { $0.1 < $1.1 }?.0
    }

    /// Maps between the screen "stage" (the unscaled area that holds the zoomed image)
    /// and image pixels. Mirrors `.scaledToFit()` followed by `.scaleEffect(zoom).offset(offset)`.
    struct Stage {
        var size: CGSize
        var imageSize: CGSize
        var zoom: CGFloat
        var offset: CGSize

        /// Aspect-fit rectangle of the image inside the stage, before zoom.
        var fit: CGRect {
            guard imageSize.width > 0, imageSize.height > 0, size.width > 0, size.height > 0 else { return .zero }
            let s = min(size.width / imageSize.width, size.height / imageSize.height)
            let w = imageSize.width * s, h = imageSize.height * s
            return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
        }

        func toStage(_ p: CGPoint) -> CGPoint {
            let f = fit
            guard imageSize.width > 0 else { return .zero }
            let s = f.width / imageSize.width
            let cx = size.width / 2, cy = size.height / 2
            let fx = f.minX + p.x * s, fy = f.minY + p.y * s
            return CGPoint(x: cx + offset.width + zoom * (fx - cx),
                           y: cy + offset.height + zoom * (fy - cy))
        }

        func toImage(_ p: CGPoint) -> CGPoint {
            let f = fit
            guard f.width > 0, zoom > 0 else { return .zero }
            let s = f.width / imageSize.width
            let cx = size.width / 2, cy = size.height / 2
            let fx = cx + (p.x - cx - offset.width) / zoom
            let fy = cy + (p.y - cy - offset.height) / zoom
            return CGPoint(x: (fx - f.minX) / s, y: (fy - f.minY) / s)
        }

        func toStage(_ r: CGRect) -> CGRect {
            let a = toStage(r.origin), b = toStage(CGPoint(x: r.maxX, y: r.maxY))
            return CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
        }

        /// Image pixels per one screen point at the current zoom.
        var pixelsPerPoint: CGFloat {
            let f = fit
            guard f.width > 0, zoom > 0 else { return 1 }
            return imageSize.width / f.width / zoom
        }
    }
}
