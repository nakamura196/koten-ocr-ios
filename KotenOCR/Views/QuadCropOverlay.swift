import SwiftUI

/// Four independent corner handles over the image. `quad` is normalized (0...1) in image space,
/// so it stays attached to the image while zooming and panning.
struct QuadCropOverlay: View {
    @Binding var quad: Quad
    /// Current on-screen frame of the image inside the named coordinate space.
    let imageFrame: CGRect
    let coordinateSpaceName: String

    private let handleSize: CGFloat = 28

    private func screen(_ p: CGPoint) -> CGPoint {
        CGPoint(x: imageFrame.minX + p.x * imageFrame.width, y: imageFrame.minY + p.y * imageFrame.height)
    }

    var body: some View {
        let s = quad.map(screen)
        ZStack {
            Canvas { ctx, size in
                var outer = Path(CGRect(origin: .zero, size: size))
                var inner = Path()
                inner.move(to: s.topLeft); inner.addLine(to: s.topRight)
                inner.addLine(to: s.bottomRight); inner.addLine(to: s.bottomLeft); inner.closeSubpath()
                outer.addPath(inner)
                ctx.fill(outer, with: .color(Color(red: 0.12, green: 0.1, blue: 0.08).opacity(0.55)),
                         style: FillStyle(eoFill: true))
                // White edge; 朱 when the shape cannot be corrected (not convex).
                ctx.stroke(inner, with: .color(quad.isConvex ? .white : KotenColor.shu), lineWidth: 2)
            }
            .allowsHitTesting(false)

            handle(\.topLeft, at: s.topLeft)
            handle(\.topRight, at: s.topRight)
            handle(\.bottomRight, at: s.bottomRight)
            handle(\.bottomLeft, at: s.bottomLeft)
        }
    }

    private static func name(of key: WritableKeyPath<Quad, CGPoint>) -> String {
        switch key {
        case \Quad.topLeft: return "topLeft"
        case \Quad.topRight: return "topRight"
        case \Quad.bottomRight: return "bottomRight"
        default: return "bottomLeft"
        }
    }

    private func handle(_ key: WritableKeyPath<Quad, CGPoint>, at pos: CGPoint) -> some View {
        // Same 朱 dot as the rectangle mode; 44pt touch target.
        Circle()
            .fill(KotenColor.shuFill)
            .frame(width: 20, height: 20)
            .overlay(Circle().stroke(Color.white, lineWidth: 3))
            .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .position(pos)
            .accessibilityIdentifier("quad_handle_\(Self.name(of: key))")
            .gesture(
                DragGesture(coordinateSpace: .named(coordinateSpaceName))
                    .onChanged { value in
                        guard imageFrame.width > 0, imageFrame.height > 0 else { return }
                        let nx = (value.location.x - imageFrame.minX) / imageFrame.width
                        let ny = (value.location.y - imageFrame.minY) / imageFrame.height
                        quad[keyPath: key] = CGPoint(x: max(0, min(1, nx)), y: max(0, min(1, ny)))
                    }
            )
    }
}

/// Rectangle / four-corner switch shown under the image in the crop screen.
struct CropModePicker: View {
    @Binding var isQuad: Bool

    var body: some View {
        Picker("", selection: $isQuad) {
            Text(String(localized: "crop_mode_rect", defaultValue: "矩形")).tag(false)
            Text(String(localized: "crop_mode_quad", defaultValue: "4点補正")).tag(true)
        }
        .pickerStyle(.segmented) // system control: Liquid Glass on iOS 26, classic on older iOS
        .frame(maxWidth: 260)
        .padding(.top, 10)
        .accessibilityIdentifier("crop_mode_picker")
    }
}
