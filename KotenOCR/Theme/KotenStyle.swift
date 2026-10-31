import SwiftUI
import UIKit

// MARK: - Hybrid design system
//
// Content (document image, recognized text, headings, home cards) uses washi paper colours,
// Mincho type and 朱 (vermilion) accents on every iOS version.
// Controls (back, share, copy, switches, toolbars, floating buttons) use Liquid Glass on
// iOS 26 and later, and solid white / 朱 plates on iOS 16–25.
// Every `#available(iOS 26, *)` check for the design lives in this file.

enum KotenColor {
    static let washi = Color("Washi")
    static let washiCard = Color("WashiCard")
    static let ink = Color("Ink")
    static let inkSecondary = Color("InkSecondary")
    /// 朱 for text, strokes and marks. Brighter in dark mode so it stays legible.
    static let shu = Color("Shu")
    /// 朱 behind white text (buttons, stamps). Kept dark enough for 4.5:1 with white.
    static let shuFill = Color("ShuFill")
    static let mount = Color("Mount")
    static let rule = Color("PaperRule")
    /// Background behind photos (crop box, camera fallback).
    static let docBackground = Color(red: 0.114, green: 0.106, blue: 0.098)
}

// MARK: - Type

extension Font {
    /// Hiragino Mincho, scaled with Dynamic Type relative to `style`.
    static func mincho(_ size: CGFloat, relativeTo style: Font.TextStyle = .body, bold: Bool = false) -> Font {
        .custom(bold ? "HiraMinProN-W6" : "HiraMinProN-W3", size: size, relativeTo: style)
    }
}

// MARK: - Paper background

struct WashiBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            KotenColor.washi
            RadialGradient(colors: [Color.white.opacity(scheme == .dark ? 0.04 : 0.6), .clear],
                           center: UnitPoint(x: 0.2, y: 0.1), startRadius: 0, endRadius: 420)
            RadialGradient(colors: [Color(red: 0.63, green: 0.47, blue: 0.27).opacity(scheme == .dark ? 0.08 : 0.12), .clear],
                           center: UnitPoint(x: 0.9, y: 0.9), startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension View {
    /// Puts the view on washi paper, filling the whole screen.
    func washiBackground() -> some View {
        background(WashiBackground())
    }

    /// Document mount: the image sits on a darker paper board with a thin rule.
    func kotenMount(padding: CGFloat = 8) -> some View {
        self
            .padding(padding)
            .background(KotenColor.mount)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(KotenColor.rule, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(color: Color(red: 0.31, green: 0.24, blue: 0.12).opacity(0.15), radius: 8, y: 6)
    }
}

// MARK: - Glass surfaces

enum KotenGlassKind {
    /// Neutral control on paper (back, share, toolbars, sheets).
    case regular
    /// The one main action on a screen (Copy, Read, Settings CTA). 朱.
    case prominent
    /// Control on top of the camera image.
    case onCamera

    /// Launch argument `-kotenSolidPlates YES` shows the iOS 16–25 plates on iOS 26, so the
    /// fallback can be checked on a simulator without an older runtime.
    static let forceSolidPlates = UserDefaults.standard.bool(forKey: "kotenSolidPlates")
}

private struct KotenGlassModifier<S: Shape>: ViewModifier {
    let kind: KotenGlassKind
    let shape: S
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26, *), !KotenGlassKind.forceSolidPlates {
            content.glassEffect(glass, in: shape)
        } else {
            content.background(fallback)
        }
    }

    @available(iOS 26, *)
    private var glass: Glass {
        var g: Glass = .regular
        if kind == .prominent { g = g.tint(KotenColor.shuFill) }
        if interactive { g = g.interactive() }
        return g
    }

    @ViewBuilder private var fallback: some View {
        switch kind {
        case .regular:
            shape.fill(KotenColor.washiCard)
                .overlay(shape.stroke(KotenColor.rule, lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
        case .prominent:
            shape.fill(KotenColor.shuFill)
        case .onCamera:
            shape.fill(Color(red: 0.17, green: 0.165, blue: 0.157))
                .overlay(shape.stroke(Color(red: 0.24, green: 0.23, blue: 0.215), lineWidth: 1))
        }
    }
}

extension View {
    /// Liquid Glass on iOS 26+, solid plate on older systems.
    func kotenGlass<S: Shape>(_ kind: KotenGlassKind = .regular, in shape: S, interactive: Bool = false) -> some View {
        modifier(KotenGlassModifier(kind: kind, shape: shape, interactive: interactive))
    }

    func kotenGlass(_ kind: KotenGlassKind = .regular, interactive: Bool = false) -> some View {
        modifier(KotenGlassModifier(kind: kind, shape: Capsule(), interactive: interactive))
    }

    /// Foreground colour that reads on the given glass kind.
    func kotenGlassForeground(_ kind: KotenGlassKind) -> some View {
        foregroundColor(kind == .regular ? KotenColor.ink : .white)
    }
}

// MARK: - Buttons

/// Button style for glass controls. Presses shrink the label (0.92) like the storyboard.
struct KotenGlassButtonStyle<S: Shape>: ButtonStyle {
    var kind: KotenGlassKind = .regular
    var shape: S

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .kotenGlassForeground(kind)
            .contentShape(shape)
            .kotenGlass(kind, in: shape, interactive: true)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == KotenGlassButtonStyle<Capsule> {
    static var kotenGlass: KotenGlassButtonStyle<Capsule> { .init(kind: .regular, shape: Capsule()) }
    static var kotenProminent: KotenGlassButtonStyle<Capsule> { .init(kind: .prominent, shape: Capsule()) }
    static var kotenCamera: KotenGlassButtonStyle<Capsule> { .init(kind: .onCamera, shape: Capsule()) }
}

extension ButtonStyle where Self == KotenGlassButtonStyle<Circle> {
    static var kotenGlassCircle: KotenGlassButtonStyle<Circle> { .init(kind: .regular, shape: Circle()) }
    static var kotenCameraCircle: KotenGlassButtonStyle<Circle> { .init(kind: .onCamera, shape: Circle()) }
}

/// Paper card button (content side, same on every iOS). Shrinks to 0.96 when pressed.
struct KotenCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .brightness(configuration.isPressed ? 0.05 : 0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Labels used by several screens

/// Back button label: chevron + text, 44pt tall.
struct KotenBackLabel: View {
    let title: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "chevron.left").font(.body.weight(.semibold))
            Text(title).font(.body.weight(.bold)).lineLimit(1)
        }
        .padding(.leading, 10)
        .padding(.trailing, 16)
        .frame(minHeight: 44)
    }
}

/// Circular icon label, 44×44.
struct KotenIconLabel: View {
    let systemName: String
    var size: CGFloat = 44
    var body: some View {
        Image(systemName: systemName)
            .font(.body.weight(.semibold))
            .frame(width: size, height: size)
    }
}

// MARK: - Seal (朱印)

/// The 典 seal used in the header, launch and empty states.
struct KotenSeal: View {
    var size: CGFloat = 40
    var rotation: Double = -2

    var body: some View {
        let border = max(2, size * 0.06)
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.1).fill(KotenColor.washi)
            RoundedRectangle(cornerRadius: size * 0.1).strokeBorder(KotenColor.shu, lineWidth: border)
            RoundedRectangle(cornerRadius: size * 0.06)
                .strokeBorder(KotenColor.shu, lineWidth: max(1, border * 0.4))
                .padding(border * 1.6)
            Text("典")
                .font(.custom("HiraMinProN-W6", fixedSize: size * 0.6))
                .foregroundColor(KotenColor.shu)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(rotation))
        .accessibilityHidden(true)
    }
}

/// The filled 朱 stamp with scan-frame corners (from icon (ii)), used when OCR finishes.
struct KotenStamp: View {
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.11).fill(KotenColor.shuFill)
            ScanCorners(inset: size * 0.13, length: size * 0.12, radius: size * 0.04)
                .stroke(Color(red: 0.953, green: 0.922, blue: 0.863),
                        style: StrokeStyle(lineWidth: max(1.5, size * 0.05), lineCap: .round))
            Text("典")
                .font(.custom("HiraMinProN-W6", fixedSize: size * 0.52))
                .foregroundColor(Color(red: 0.953, green: 0.922, blue: 0.863))
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(-6))
        .accessibilityHidden(true)
    }
}

/// Four rounded scan-frame corners.
struct ScanCorners: Shape {
    var inset: CGFloat = 0
    var length: CGFloat = 34
    var radius: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let l = min(length, r.width / 2, r.height / 2)
        var p = Path()
        // top-left
        p.move(to: CGPoint(x: r.minX, y: r.minY + l))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + radius))
        p.addQuadCurve(to: CGPoint(x: r.minX + radius, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + l, y: r.minY))
        // top-right
        p.move(to: CGPoint(x: r.maxX - l, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + radius), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + l))
        // bottom-right
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - l))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: r.maxX - radius, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - l, y: r.maxY))
        // bottom-left
        p.move(to: CGPoint(x: r.minX + l, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + radius, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - radius), control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - l))
        return p
    }
}

// MARK: - Motion

enum KotenMotion {
    /// Spring with little bounce used for moves (storyboard: "spring 0.35–0.45 s").
    static func spring(_ response: Double = 0.4, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: response, dampingFraction: 0.86)
    }

    /// Screen change: zoom from where it was pressed, or a cross-fade with Reduce Motion.
    static func screenTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity)
    }

    /// Content rising from below (cards, sheets), or a fade with Reduce Motion.
    static func rise(_ distance: CGFloat = 16, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .offset(y: distance).combined(with: .opacity)
    }
}

enum KotenHaptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}

// MARK: - One-time coach marks

enum CoachMark: String, CaseIterable {
    case shutter = "coachShutterShown"
    case cropCorner = "coachCropCornerShown"

    var isShown: Bool { UserDefaults.standard.bool(forKey: rawValue) }

    func markShown() { UserDefaults.standard.set(true, forKey: rawValue) }

    static func resetAll() {
        allCases.forEach { UserDefaults.standard.removeObject(forKey: $0.rawValue) }
    }
}

/// Speech bubble with a 朱 border and a pointer. Mincho text, since it is guidance content.
struct CoachBubble: View {
    enum Pointer { case up, down }
    let text: String
    var pointer: Pointer = .down
    /// Horizontal position of the pointer, 0...1.
    var pointerX: CGFloat = 0.5

    var body: some View {
        Text(text)
            .font(.mincho(18, relativeTo: .headline, bold: true))
            .foregroundColor(KotenColor.ink)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                BubbleShape(pointer: pointer, pointerX: pointerX)
                    .fill(KotenColor.washiCard)
                    .shadow(color: .black.opacity(0.3), radius: 12, y: 8)
            )
            .overlay(BubbleShape(pointer: pointer, pointerX: pointerX).stroke(KotenColor.shu, lineWidth: 3))
            .padding(pointer == .down ? .bottom : .top, 12)
            .accessibilityAddTraits(.isStaticText)
    }
}

private struct BubbleShape: Shape {
    let pointer: CoachBubble.Pointer
    let pointerX: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 16
        let tip: CGFloat = 12
        let x = min(max(rect.minX + radius + tip, rect.minX + rect.width * pointerX), rect.maxX - radius - tip)
        var p = Path()
        // Clockwise outline from the top-left corner, with the pointer drawn into the edge.
        p.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        if pointer == .up {
            p.addLine(to: CGPoint(x: x - tip, y: rect.minY))
            p.addLine(to: CGPoint(x: x, y: rect.minY - tip))
            p.addLine(to: CGPoint(x: x + tip, y: rect.minY))
        }
        p.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius), control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        if pointer == .down {
            p.addLine(to: CGPoint(x: x + tip, y: rect.maxY))
            p.addLine(to: CGPoint(x: x, y: rect.maxY + tip))
            p.addLine(to: CGPoint(x: x - tip, y: rect.maxY))
        }
        p.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        p.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
