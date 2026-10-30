import SwiftUI

/// Small level indicator plus an advisory hint. Never intercepts touches, never blocks the shutter.
/// Rule: held facing down (flat over a table) -> compare against parallel; held upright (wall)
/// -> compare against vertical; anything in between -> show nothing.
struct LevelGuideView: View {
    @AppStorage(TiltMonitor.defaultsKey) private var enabled = true
    @StateObject private var monitor = TiltMonitor()
    /// Shown as a tappable secondary line under the hint when non-nil.
    var onTryScanner: (() -> Void)?
    /// Reports whether the tilt hint is on screen, so the camera can hide its frame hint meanwhile.
    var isHintShowing: Binding<Bool>? = nil

    private var hintVisible: Bool { enabled && monitor.state.isActive && monitor.state.showsHint }

    var body: some View {
        VStack(spacing: 8) {
            if enabled, monitor.state.isActive {
                bubble
                if monitor.state.showsHint {
                    Text(String(localized: "tilt_hint", defaultValue: "資料と平行に構えてください"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .kotenGlass(.onCamera, in: Capsule())
                        .accessibilityIdentifier("tilt_hint")
                    if let onTryScanner {
                        Button(action: onTryScanner) {
                            Label(String(localized: "tilt_try_scanner", defaultValue: "書類スキャンも使えます"),
                                  systemImage: "doc.viewfinder")
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 14)
                                .frame(minHeight: 36)
                        }
                        .buttonStyle(.kotenCamera)
                        .accessibilityIdentifier("tilt_try_scanner")
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: monitor.state.showsHint)
        .onAppear { if enabled { monitor.start() } }
        .onDisappear {
            monitor.stop()
            isHintShowing?.wrappedValue = false
        }
        .onChange(of: hintVisible) { isHintShowing?.wrappedValue = $0 }
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
            Circle().stroke(Color.white.opacity(0.7), lineWidth: 1.5).frame(width: r * 2 - 6, height: r * 2 - 6)
            Rectangle().fill(Color.white.opacity(0.4)).frame(width: r * 2 - 6, height: 0.5)
            Rectangle().fill(Color.white.opacity(0.4)).frame(width: 0.5, height: r * 2 - 6)
            // Level: white dot. Tilted: 朱 (bright variant, readable on the camera image).
            Circle().fill(ok ? Color.white : Color(red: 0.878, green: 0.408, blue: 0.298))
                .frame(width: 12, height: 12)
                .offset(x: dx * (r - 9), y: dy * (r - 9))
        }
        .frame(width: r * 2, height: r * 2)
        .kotenGlass(.onCamera, in: Circle())
        .accessibilityHidden(true)
    }
}
