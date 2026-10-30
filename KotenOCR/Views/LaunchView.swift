import SwiftUI

/// Launch → home (storyboard a). Washi appears, the 典 seal is pressed (1.25 → 1.0, light
/// haptic), the name rises, a short pause, then the seal and name move into the home header
/// (matched geometry with HomeView). Later launches skip the press and take about 0.5 s.
struct LaunchView: View {
    let namespace: Namespace.ID
    /// Play the full stamp sequence (first launch only).
    let fullStamp: Bool
    /// Show a spinner when the models are still loading after the animation.
    let showsProgress: Bool
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage = 0
    @State private var finished = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            KotenSeal(size: 120, rotation: -3)
                .scaleEffect(stage >= 1 ? 1 : 1.25)
                .opacity(stage >= 1 ? 1 : 0)
                .matchedGeometryEffect(id: "brandSeal", in: namespace, properties: .position)
            Text("KotenOCR")
                .font(.mincho(34, relativeTo: .largeTitle, bold: true))
                .tracking(2)
                .foregroundColor(KotenColor.ink)
                .opacity(stage >= 2 ? 1 : 0)
                .offset(y: stage >= 2 || reduceMotion ? 0 : 8)
                .matchedGeometryEffect(id: "brandName", in: namespace, properties: .position)
                .padding(.top, 28)
            Text("brand_tagline")
                .font(.mincho(17, relativeTo: .body))
                .tracking(1.5)
                .foregroundColor(KotenColor.inkSecondary)
                .multilineTextAlignment(.center)
                .opacity(stage >= 3 ? 1 : 0)
                .padding(.top, 10)
                .padding(.horizontal, 24)
            Spacer()
            ProgressView()
                .tint(KotenColor.shu)
                .opacity(showsProgress && finished ? 1 : 0)
                .padding(.bottom, 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("loading_models"))
        .onAppear(perform: play)
    }

    private func play() {
        guard stage == 0 else { return }
        if reduceMotion || !fullStamp {
            withAnimation(.easeOut(duration: 0.25)) { stage = 3 }
            after(0.5) { finish() }
            return
        }
        // 200–480 ms: the seal is pressed.
        after(0.2) {
            KotenHaptics.impact(.light)
            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) { stage = 1 }
        }
        // 480–700 ms: the name rises 8pt.
        after(0.48) { withAnimation(.easeOut(duration: 0.22)) { stage = 2 } }
        // 700–900 ms: the tagline, then a short pause.
        after(0.7) { withAnimation(.easeOut(duration: 0.2)) { stage = 3 } }
        after(0.9) { finish() }
    }

    private func finish() {
        finished = true
        onFinished()
    }

    private func after(_ seconds: Double, _ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: block)
    }
}
