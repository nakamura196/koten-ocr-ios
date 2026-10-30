import SwiftUI

struct CropView: View {
    let image: CGImage
    /// Receives the cropped image and the (possibly rotated) image it was cropped from.
    let onCrop: (_ cropped: CGImage, _ source: CGImage) -> Void
    /// Receives the displayed image, i.e. including any rotation applied in this view.
    let onSkip: (_ displayed: CGImage) -> Void
    let onCancel: () -> Void

    @State private var cropRect: CGRect = .zero
    @State private var imageFrame: CGRect = .zero
    @State private var initializedCrop = false
    @State private var currentImage: CGImage?
    @State private var containerSize: CGSize = .zero
    @State private var moveStartRect: CGRect?

    // Four-corner mode (normalized image coordinates)
    @State private var isQuadMode = false
    @State private var quad: Quad = .unit

    // Zoom & Pan
    @State private var zoomScale: CGFloat = 1.0
    @State private var baseZoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var basePanOffset: CGSize = .zero

    // Design: handles appear one by one; one-time coach mark on a corner
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var handlesShown = 0
    @State private var showCornerCoach = false

    private let handleSize: CGFloat = 28
    private let minCropSize: CGFloat = 50

    private var displayImage: CGImage {
        currentImage ?? image
    }

    var body: some View {
        ZStack {
            WashiBackground()

            VStack(spacing: 0) {
                // Top bar
                HStack(spacing: 10) {
                    Button(action: onCancel) {
                        KotenBackLabel(title: String(localized: "ocr_error_retake", defaultValue: "撮り直す"))
                    }
                    .buttonStyle(.kotenGlass)
                    .accessibilityIdentifier("crop_cancel_button")
                    Spacer(minLength: 8)
                    if zoomScale > 1.01 {
                        Button(action: resetZoom) {
                            KotenIconLabel(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.kotenGlassCircle)
                        .accessibilityLabel(Text("crop_reset_zoom"))
                        .transition(.opacity)
                    }
                    Button(action: rotateImage) {
                        KotenIconLabel(systemName: "rotate.right")
                    }
                    .buttonStyle(.kotenGlassCircle)
                    .accessibilityLabel(Text("crop_rotate"))
                }
                .overlay {
                    if !typeSize.isAccessibilitySize {
                        Text(String(localized: "crop_title", defaultValue: "Crop"))
                            .font(.mincho(18, relativeTo: .headline, bold: true))
                            .foregroundColor(KotenColor.ink)
                            .lineLimit(1)
                            .padding(.horizontal, 130)
                            .allowsHitTesting(false)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .animation(.easeInOut(duration: 0.2), value: zoomScale > 1.01)

                // Image + crop overlay
                GeometryReader { geo in
                    let img = displayImage
                    let cSize = geo.size
                    let baseRect = fitRect(
                        imageWidth: CGFloat(img.width),
                        imageHeight: CGFloat(img.height),
                        containerSize: cSize
                    )
                    let zoomedRect = zoomedImageRect(baseRect: baseRect)

                    ZStack {
                        // Dark board behind the photo, so the white crop frame reads clearly
                        RoundedRectangle(cornerRadius: 6).fill(KotenColor.docBackground)

                        // Image at zoomed position, clipped to the board (handles are not clipped)
                        ZStack {
                            Image(decorative: img, scale: 1.0)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: zoomedRect.width, height: zoomedRect.height)
                                .position(x: zoomedRect.midX, y: zoomedRect.midY)
                        }
                        .frame(width: cSize.width, height: cSize.height)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        // Crop overlays (only after initialization)
                        if initializedCrop && isQuadMode {
                            QuadCropOverlay(quad: $quad, imageFrame: imageFrame, coordinateSpaceName: "cropContainer")
                        }
                        if initializedCrop && !isQuadMode {
                            CropDimOverlay(cropRect: cropRect, containerSize: cSize)
                                .allowsHitTesting(false)

                            Rectangle()
                                .stroke(Color.white, lineWidth: 2)
                                .frame(width: cropRect.width, height: cropRect.height)
                                .position(x: cropRect.midX, y: cropRect.midY)
                                .allowsHitTesting(false)

                            CropGridLines(cropRect: cropRect)
                                .allowsHitTesting(false)

                            // Center drag (move crop rect)
                            Rectangle()
                                .fill(Color.white.opacity(0.001))
                                .frame(width: max(0, cropRect.width - handleSize * 2),
                                       height: max(0, cropRect.height - handleSize * 2))
                                .position(x: cropRect.midX, y: cropRect.midY)
                                .gesture(moveDrag)

                            // Corner handles
                            cornerHandle(corner: .topLeft)
                            cornerHandle(corner: .topRight)
                            cornerHandle(corner: .bottomLeft)
                            cornerHandle(corner: .bottomRight)

                            // Edge handles
                            edgeHandle(edge: .top)
                            edgeHandle(edge: .bottom)
                            edgeHandle(edge: .leading)
                            edgeHandle(edge: .trailing)
                        }

                        if showCornerCoach {
                            CoachBubble(text: String(localized: "coach_crop_corner", defaultValue: "角を動かして\n範囲を選ぶ"),
                                        pointer: .up, pointerX: 0.18)
                                .frame(maxWidth: min(cSize.width - 24, 280))
                                .fixedSize(horizontal: true, vertical: false)
                                .position(x: min(max(cropRect.minX + 100, 110), cSize.width - 110),
                                          y: min(cropRect.minY + 70, cSize.height - 50))
                                .allowsHitTesting(false)
                                .transition(.opacity)
                        }

                        // Zoom level indicator
                        if zoomScale > 1.01 {
                            VStack {
                                HStack {
                                    Spacer()
                                    Text(String(format: "%.1fx", zoomScale))
                                        .font(.caption2.bold())
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.black.opacity(0.5))
                                        .cornerRadius(10)
                                        .padding(8)
                                }
                                Spacer()
                            }
                        }
                    }
                    // Pinch zoom gesture on the ENTIRE container
                    .contentShape(Rectangle())
                    .gesture(pinchGesture)
                    // Two-finger pan gesture on the container
                    .gesture(panGesture)
                    .coordinateSpace(name: "cropContainer")
                    .simultaneousGesture(TapGesture().onEnded { dismissCornerCoach() })
                    .simultaneousGesture(DragGesture(minimumDistance: 1).onChanged { _ in dismissCornerCoach() })
                    .onAppear {
                        containerSize = cSize
                        initializeCrop(baseRect: baseRect)
                        revealHandles()
                    }
                    .onChange(of: cSize) { newSize in
                        containerSize = newSize
                        let newBase = fitRect(
                            imageWidth: CGFloat(img.width),
                            imageHeight: CGFloat(img.height),
                            containerSize: newSize
                        )
                        let newZoomed = zoomedImageRect(baseRect: newBase)
                        updateImageFrameAndCrop(newZoomed: newZoomed)
                    }
                    .onChange(of: zoomScale) { _ in
                        let newZoomed = zoomedImageRect(baseRect: baseRect)
                        updateImageFrameAndCrop(newZoomed: newZoomed)
                    }
                    .onChange(of: panOffset) { _ in
                        let newZoomed = zoomedImageRect(baseRect: baseRect)
                        updateImageFrameAndCrop(newZoomed: newZoomed)
                    }
                }

                .padding(.horizontal, 12)
                .padding(.top, 10)

                Text("crop_tip")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(KotenColor.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 26)
                    .padding(.top, 12)

                CropModePicker(isQuad: $isQuadMode)
                    .onChange(of: isQuadMode) { on in if on { prepareQuad() } }

                // Bottom glass toolbar
                HStack(spacing: 12) {
                    Button(action: { onSkip(displayImage) }) {
                        Text(String(localized: "crop_skip", defaultValue: "Skip"))
                            .font(.headline)
                            .padding(.horizontal, 22)
                            .frame(minHeight: 50)
                    }
                    .buttonStyle(.kotenGlass)
                    .accessibilityIdentifier("skip_crop_button")

                    Spacer(minLength: 0)

                    Button(action: performCrop) {
                        Text(String(localized: "crop_apply", defaultValue: "Crop"))
                            .font(.headline.weight(.heavy))
                            .padding(.horizontal, 26)
                            .frame(minWidth: 120, minHeight: 50)
                    }
                    .buttonStyle(.kotenProminent)
                    .accessibilityIdentifier("crop_button")
                }
                .padding(10)
                .kotenGlass(.regular, in: RoundedRectangle(cornerRadius: 36, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 12)
            }
        }
        .onAppear {
            currentImage = image
            if !CoachMark.cropCorner.isShown && ProcessInfo.processInfo.environment["TEST_IMAGE_PATH"]?.isEmpty ?? true {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    withAnimation(.easeOut(duration: 0.3)) { showCornerCoach = true }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 6.6) { dismissCornerCoach() }
            }
        }
    }

    private func dismissCornerCoach() {
        guard showCornerCoach else { return }
        CoachMark.cropCorner.markShown()
        withAnimation(.easeOut(duration: 0.2)) { showCornerCoach = false }
    }

    /// The 朱 corner dots appear in turn, 40 ms apart (all at once with Reduce Motion).
    private func revealHandles() {
        guard handlesShown == 0 else { return }
        if reduceMotion {
            handlesShown = 4
            return
        }
        for i in 1...4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04 * Double(i)) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { handlesShown = max(handlesShown, i) }
            }
        }
    }

    // MARK: - Layout Calculation

    private func fitRect(imageWidth: CGFloat, imageHeight: CGFloat, containerSize: CGSize) -> CGRect {
        guard imageWidth > 0, imageHeight > 0, containerSize.width > 0, containerSize.height > 0 else {
            return .zero
        }
        let scale = min(containerSize.width / imageWidth, containerSize.height / imageHeight)
        let w = imageWidth * scale
        let h = imageHeight * scale
        return CGRect(
            x: (containerSize.width - w) / 2,
            y: (containerSize.height - h) / 2,
            width: w,
            height: h
        )
    }

    private func zoomedImageRect(baseRect: CGRect) -> CGRect {
        let w = baseRect.width * zoomScale
        let h = baseRect.height * zoomScale
        let x = baseRect.midX - w / 2 + panOffset.width
        let y = baseRect.midY - h / 2 + panOffset.height
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func initializeCrop(baseRect: CGRect) {
        guard !initializedCrop, baseRect.width > 0 else { return }
        imageFrame = baseRect
        cropRect = baseRect
        initializedCrop = true
    }

    private func updateImageFrameAndCrop(newZoomed: CGRect) {
        let oldFrame = imageFrame
        imageFrame = newZoomed
        guard initializedCrop, oldFrame.width > 0, newZoomed.width > 0 else { return }
        // Scale crop rect proportionally
        let sx = newZoomed.width / oldFrame.width
        let sy = newZoomed.height / oldFrame.height
        cropRect = CGRect(
            x: newZoomed.minX + (cropRect.minX - oldFrame.minX) * sx,
            y: newZoomed.minY + (cropRect.minY - oldFrame.minY) * sy,
            width: cropRect.width * sx,
            height: cropRect.height * sy
        )
    }

    // MARK: - Zoom & Pan Gestures

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let newScale = max(1.0, min(baseZoomScale * value, 8.0))
                zoomScale = newScale
            }
            .onEnded { value in
                baseZoomScale = zoomScale
                clampPan()
            }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                guard zoomScale > 1.01 else { return }
                panOffset = CGSize(
                    width: basePanOffset.width + value.translation.width,
                    height: basePanOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                basePanOffset = panOffset
                clampPan()
            }
    }

    private func clampPan() {
        guard containerSize.width > 0 else { return }
        let img = displayImage
        let baseRect = fitRect(
            imageWidth: CGFloat(img.width),
            imageHeight: CGFloat(img.height),
            containerSize: containerSize
        )
        let halfExtraW = max(0, (baseRect.width * zoomScale - containerSize.width) / 2)
        let halfExtraH = max(0, (baseRect.height * zoomScale - containerSize.height) / 2)
        panOffset.width = min(halfExtraW, max(-halfExtraW, panOffset.width))
        panOffset.height = min(halfExtraH, max(-halfExtraH, panOffset.height))
        basePanOffset = panOffset
    }

    private func resetZoom() {
        withAnimation(.easeInOut(duration: 0.25)) {
            zoomScale = 1.0
            baseZoomScale = 1.0
            panOffset = .zero
            basePanOffset = .zero
        }
    }

    // MARK: - Rotation

    private func rotateImage() {
        guard let rotated = displayImage.rotated90Clockwise() else { return }
        currentImage = rotated
        isQuadMode = false
        initializedCrop = false
        zoomScale = 1.0
        baseZoomScale = 1.0
        panOffset = .zero
        basePanOffset = .zero
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if !initializedCrop, containerSize.width > 0 {
                let baseRect = fitRect(
                    imageWidth: CGFloat(displayImage.width),
                    imageHeight: CGFloat(displayImage.height),
                    containerSize: containerSize
                )
                initializeCrop(baseRect: baseRect)
            }
        }
    }

    // MARK: - Handles

    private enum Corner { case topLeft, topRight, bottomLeft, bottomRight }
    private enum Edge { case top, bottom, leading, trailing }

    private func cornerHandle(corner: Corner) -> some View {
        let pos: CGPoint = {
            switch corner {
            case .topLeft: return CGPoint(x: cropRect.minX, y: cropRect.minY)
            case .topRight: return CGPoint(x: cropRect.maxX, y: cropRect.minY)
            case .bottomLeft: return CGPoint(x: cropRect.minX, y: cropRect.maxY)
            case .bottomRight: return CGPoint(x: cropRect.maxX, y: cropRect.maxY)
            }
        }()

        let order: Int = {
            switch corner {
            case .topLeft: return 1
            case .topRight: return 2
            case .bottomRight: return 3
            case .bottomLeft: return 4
            }
        }()
        let visible = handlesShown >= order
        // 朱 dot with a white ring; the touch target stays 44pt.
        return Circle()
            .fill(KotenColor.shuFill)
            .frame(width: 20, height: 20)
            .overlay(Circle().stroke(Color.white, lineWidth: 3))
            .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
            .scaleEffect(visible ? 1 : 0.2)
            .opacity(visible ? 1 : 0)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .position(pos)
            .gesture(cornerDrag(corner: corner))
    }

    private func edgeHandle(edge: Edge) -> some View {
        let pos: CGPoint = {
            switch edge {
            case .top: return CGPoint(x: cropRect.midX, y: cropRect.minY)
            case .bottom: return CGPoint(x: cropRect.midX, y: cropRect.maxY)
            case .leading: return CGPoint(x: cropRect.minX, y: cropRect.midY)
            case .trailing: return CGPoint(x: cropRect.maxX, y: cropRect.midY)
            }
        }()

        let isHorizontal = (edge == .top || edge == .bottom)
        let w: CGFloat = isHorizontal ? 44 : handleSize / 2
        let h: CGFloat = isHorizontal ? handleSize / 2 : 44

        return RoundedRectangle(cornerRadius: 3)
            .fill(Color.white)
            .frame(width: w, height: h)
            .shadow(radius: 2)
            .position(pos)
            .gesture(edgeDrag(edge: edge))
    }

    // MARK: - Crop Drag Gestures

    private var moveDrag: some Gesture {
        DragGesture(coordinateSpace: .named("cropContainer"))
            .onChanged { value in
                // translation is cumulative since the drag began, so apply it to the rect at drag start
                let start = moveStartRect ?? cropRect
                moveStartRect = start
                cropRect = CropGeometry.moved(start, by: value.translation, within: imageFrame)
            }
            .onEnded { _ in moveStartRect = nil }
    }

    private func cornerDrag(corner: Corner) -> some Gesture {
        DragGesture()
            .onChanged { value in
                var r = cropRect
                switch corner {
                case .topLeft:
                    let newX = min(value.location.x, r.maxX - minCropSize)
                    let newY = min(value.location.y, r.maxY - minCropSize)
                    r = CGRect(x: newX, y: newY, width: r.maxX - newX, height: r.maxY - newY)
                case .topRight:
                    let newMaxX = max(value.location.x, r.minX + minCropSize)
                    let newY = min(value.location.y, r.maxY - minCropSize)
                    r = CGRect(x: r.minX, y: newY, width: newMaxX - r.minX, height: r.maxY - newY)
                case .bottomLeft:
                    let newX = min(value.location.x, r.maxX - minCropSize)
                    let newMaxY = max(value.location.y, r.minY + minCropSize)
                    r = CGRect(x: newX, y: r.minY, width: r.maxX - newX, height: newMaxY - r.minY)
                case .bottomRight:
                    let newMaxX = max(value.location.x, r.minX + minCropSize)
                    let newMaxY = max(value.location.y, r.minY + minCropSize)
                    r = CGRect(x: r.minX, y: r.minY, width: newMaxX - r.minX, height: newMaxY - r.minY)
                }
                cropRect = clampToImage(r)
            }
    }

    private func edgeDrag(edge: Edge) -> some Gesture {
        DragGesture()
            .onChanged { value in
                var r = cropRect
                switch edge {
                case .top:
                    let newY = min(value.location.y, r.maxY - minCropSize)
                    r = CGRect(x: r.minX, y: newY, width: r.width, height: r.maxY - newY)
                case .bottom:
                    let newMaxY = max(value.location.y, r.minY + minCropSize)
                    r = CGRect(x: r.minX, y: r.minY, width: r.width, height: newMaxY - r.minY)
                case .leading:
                    let newX = min(value.location.x, r.maxX - minCropSize)
                    r = CGRect(x: newX, y: r.minY, width: r.maxX - newX, height: r.height)
                case .trailing:
                    let newMaxX = max(value.location.x, r.minX + minCropSize)
                    r = CGRect(x: r.minX, y: r.minY, width: newMaxX - r.minX, height: r.height)
                }
                cropRect = clampToImage(r)
            }
    }

    private func clampToImage(_ rect: CGRect) -> CGRect {
        var r = rect
        r.origin.x = max(imageFrame.minX, r.origin.x)
        r.origin.y = max(imageFrame.minY, r.origin.y)
        if r.maxX > imageFrame.maxX { r.size.width = imageFrame.maxX - r.origin.x }
        if r.maxY > imageFrame.maxY { r.size.height = imageFrame.maxY - r.origin.y }
        r.size.width = max(minCropSize, r.size.width)
        r.size.height = max(minCropSize, r.size.height)
        return r
    }

    // MARK: - Crop execution

    /// Seeds the corners from the current rectangle, then tries to snap them to a detected page.
    private func prepareQuad() {
        guard imageFrame.width > 0, imageFrame.height > 0 else { return }
        quad = Quad(rect: CGRect(x: (cropRect.minX - imageFrame.minX) / imageFrame.width,
                                 y: (cropRect.minY - imageFrame.minY) / imageFrame.height,
                                 width: cropRect.width / imageFrame.width,
                                 height: cropRect.height / imageFrame.height))
        let img = displayImage
        DispatchQueue.global(qos: .userInitiated).async {
            guard let found = PerspectiveCrop.detectPage(in: img) else { return }
            DispatchQueue.main.async { if isQuadMode, displayImage === img { quad = found } }
        }
    }

    private func performCrop() {
        let img = displayImage
        if isQuadMode, let rectified = PerspectiveCrop.rectify(img, normalizedQuad: quad) {
            onCrop(rectified, img)
            return
        }
        guard let rect = CropGeometry.pixelRect(
            cropRect: cropRect,
            imageFrame: imageFrame,
            imageSize: CGSize(width: img.width, height: img.height)
        ), let cropped = img.cropping(to: rect) else {
            onSkip(img)
            return
        }
        onCrop(cropped, img)
    }
}

// MARK: - Dim Overlay

private struct CropDimOverlay: View {
    let cropRect: CGRect
    let containerSize: CGSize

    var body: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(Color(red: 0.12, green: 0.1, blue: 0.08).opacity(0.55))
            )
            context.blendMode = .destinationOut
            context.fill(
                Path(cropRect),
                with: .color(.white)
            )
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Grid Lines

private struct CropGridLines: View {
    let cropRect: CGRect

    var body: some View {
        Canvas { context, _ in
            let thirdW = cropRect.width / 3
            let thirdH = cropRect.height / 3
            var path = Path()
            for i in 1...2 {
                let x = cropRect.minX + thirdW * CGFloat(i)
                path.move(to: CGPoint(x: x, y: cropRect.minY))
                path.addLine(to: CGPoint(x: x, y: cropRect.maxY))
            }
            for i in 1...2 {
                let y = cropRect.minY + thirdH * CGFloat(i)
                path.move(to: CGPoint(x: cropRect.minX, y: y))
                path.addLine(to: CGPoint(x: cropRect.maxX, y: y))
            }
            context.stroke(path, with: .color(.white.opacity(0.4)), lineWidth: 0.5)
        }
    }
}

