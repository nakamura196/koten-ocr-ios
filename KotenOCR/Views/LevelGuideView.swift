import SwiftUI

/// Small level indicator plus an advisory hint. Never intercepts touches, never blocks the shutter.
/// Rule: held facing down (flat over a table) -> compare against parallel; held upright (wall)
/// -> compare against vertical; anything in between -> show nothing.
struct LevelGuideView: View {
    @AppStorage(TiltMonitor.defaultsKey) private var enabled = true
    @StateObject private var monitor = TiltMonitor()
    /// Shown as a tappable secondary line under the hint when non-nil.
    var onTryScanner: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            if enabled, monitor.state.isActive {
                bubble
                if monitor.state.showsHint {
                    Text(String(localized: "tilt_hint", defaultValue: "資料と平行に構えてください"))
                        .font(.footnote.weight(.medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Capsule())
                        .accessibilityIdentifier("tilt_hint")
                    if let onTryScanner {
                        Button(action: onTryScanner) {
                            Text(String(localized: "tilt_try_scanner", defaultValue: "書類スキャンも使えます"))
                                .font(.caption)
                                .underline()
                                .foregroundColor(.white)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Color.black.opacity(0.45))
                                .clipShape(Capsule())
                        }
                        .accessibilityIdentifier("tilt_try_scanner")
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: monitor.state.showsHint)
        .onAppear { if enabled { monitor.start() } }
        .onDisappear { monitor.stop() }
        .onChange(of: enabled) { on in on ? monitor.start() : monitor.stop() }
    }

    private var bubble: some View {
        let r: CGFloat = 22
        let ok = !monitor.state.showsHint
        let g = monitor.gravity
        // Flat: bubble drifts toward the low side (x, y). Upright: horizontal = roll, vertical = pitch.
        var dx = CGFloat(g.x), dy: CGFloat
        switch monitor.state {
        case .upright: dy = CGFloat(g.z)
        default: dy = CGFloat(-g.y)
        }
        dx = max(-1, min(1, dx * 3)); dy = max(-1, min(1, dy * 3))
        return ZStack {
            Circle().stroke(Color.white.opacity(0.7), lineWidth: 1.5).frame(width: r * 2, height: r * 2)
            Rectangle().fill(Color.white.opacity(0.4)).frame(width: r * 2, height: 0.5)
            Rectangle().fill(Color.white.opacity(0.4)).frame(width: 0.5, height: r * 2)
            Circle().fill(ok ? Color.green : Color.orange).frame(width: 12, height: 12)
                .offset(x: dx * (r - 6), y: dy * (r - 6))
        }
        .frame(width: r * 2, height: r * 2)
        .background(Color.black.opacity(0.35).clipShape(Circle()))
        .accessibilityHidden(true)
    }
}
