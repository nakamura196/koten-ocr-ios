import SwiftUI

struct CropView: View {
    let image: CGImage
    let onCrop: (CGImage) -> Void
    let onSkip: () -> Void
    let onCancel: () -> Void

    @State private var cropRect: CGRect = .zero
    @State private var imageFrame: CGRect = .zero
    @State private var initializedCrop = false
    @State private var currentImage: CGImage?
    @State private var containerSize: CGSize = .zero

    // Zoom & Pan
    @State private var zoomScale: CGFloat = 1.0
    @State private var baseZoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var basePanOffset: CGSize = .zero

    private let handleSize: CGFloat = 28
    private let minCropSize: CGFloat = 50

    private var displayImage: CGImage {
        currentImage ?? image
    }

    var body: some View {
        ZStack {
            Color(white: 0.2).ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button(action: onCancel) {
                        Text(String(localized: "cancel", defaultValue: "Cancel"))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    Text(String(localized: "crop_title", defaultValue: "Crop"))
                        .foregroundColor(.white)
                        .font(.headline)
                    Spacer()
                    HStack(spacing: 16) {
                        if zoomScale > 1.01 {
                            Button(action: resetZoom) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 18))
                                    .foregroundColor(.yellow)
                            }
                            .transition(.opacity)
                        }
                        Button(action: rotateImage) {
                            Image(systemName: "rotate.right")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                        }
                        .accessibilityLabel(Text("crop_rotate"))
                    }
                }
                .padding()
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
                        // Distinct background for the zoomable area
                        Color(white: 0.2)

                        // Image at zoomed position
                        Image(decorative: img, scale: 1.0)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: zoomedRect.width, height: zoomedRect.height)
                            .position(x: zoomedRect.midX, y: zoomedRect.midY)

                        // Crop overlays (only after initialization)
                        if initializedCrop {
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
                    .onAppear {
                        containerSize = cSize
                        initializeCrop(baseRect: baseRect)
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

                // Bottom buttons
                HStack(spacing: 40) {
                    Button(action: { onSkip() }) {
                        Text(String(localized: "crop_skip", defaultValue: "Skip"))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(8)
                    }

                    Button(action: performCrop) {
                        Text(String(localized: "crop_apply", defaultValue: "Crop"))
                            .foregroundColor(.black)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.white)
                            .cornerRadius(8)
                    }
                }
                .padding(.vertical, 20)
            }
        }
        .onAppear {
            currentImage = image
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
        let inset = min(baseRect.width, baseRect.height) * 0.05
        cropRect = baseRect.insetBy(dx: inset, dy: inset)
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

        return Circle()
            .fill(Color.white)
            .frame(width: handleSize, height: handleSize)
            .shadow(radius: 2)
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
        DragGesture()
            .onChanged { value in
                var newRect = cropRect.offsetBy(dx: value.translation.width, dy: value.translation.height)
                newRect.origin.x = max(imageFrame.minX, min(newRect.origin.x, imageFrame.maxX - newRect.width))
                newRect.origin.y = max(imageFrame.minY, min(newRect.origin.y, imageFrame.maxY - newRect.height))
                cropRect = newRect
            }
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

    private func performCrop() {
        let img = displayImage
        guard imageFrame.width > 0, imageFrame.height > 0 else {
            onSkip()
            return
        }

        let scaleX = CGFloat(img.width) / imageFrame.width
        let scaleY = CGFloat(img.height) / imageFrame.height

        let pixelRect = CGRect(
            x: (cropRect.minX - imageFrame.minX) * scaleX,
            y: (cropRect.minY - imageFrame.minY) * scaleY,
            width: cropRect.width * scaleX,
            height: cropRect.height * scaleY
        ).integral

        let clampedRect = pixelRect.intersection(
            CGRect(x: 0, y: 0, width: img.width, height: img.height)
        )

        guard !clampedRect.isEmpty,
              let cropped = img.cropping(to: clampedRect) else {
            onSkip()
            return
        }

        onCrop(cropped)
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
                with: .color(.black.opacity(0.5))
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

