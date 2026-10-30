import Foundation
import CoreMotion

/// How the phone is held, judged from the gravity vector (device frame: x right, y up, z out of the screen).
/// The back camera looks along -z. Straight down over a table means gravity = (0, 0, -1).
enum TiltState: Equatable {
    /// Camera points roughly at the floor/table. `deviation` is degrees away from straight down.
    case flat(deviation: Double)
    /// Camera points roughly horizontally (wall). `deviation` is degrees away from horizontal.
    case upright(deviation: Double)
    /// In between (or pointing up): no guidance.
    case tilted

    /// Camera axis within this many degrees of straight down / horizontal counts as flat / upright.
    static let zoneHalfWidth = 30.0
    /// Deviation above which the hint is shown.
    static let hintThreshold = 8.0

    static func classify(x: Double, y: Double, z: Double) -> TiltState {
        let norm = (x * x + y * y + z * z).squareRoot()
        guard norm > 0.3 else { return .tilted }
        // Angle between the camera axis (-z) and gravity.
        let fromDown = acos(max(-1, min(1, -z / norm))) * 180 / .pi
        if fromDown <= zoneHalfWidth { return .flat(deviation: fromDown) }
        let fromHorizontal = abs(fromDown - 90)
        if fromHorizontal <= zoneHalfWidth { return .upright(deviation: fromHorizontal) }
        return .tilted
    }

    var showsHint: Bool {
        switch self {
        case .flat(let d), .upright(let d): return d > Self.hintThreshold
        case .tilted: return false
        }
    }

    var isActive: Bool { self != .tilted }
}

/// Publishes the gravity vector and the derived TiltState. Advisory only.
final class TiltMonitor: ObservableObject {
    static let defaultsKey = "showTiltGuide"

    @Published private(set) var state: TiltState = .tilted
    @Published private(set) var gravity: (x: Double, y: Double, z: Double) = (0, 0, 0)

    private let manager = CMMotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 15.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let g = motion?.gravity else { return }
            let s = TiltState.classify(x: g.x, y: g.y, z: g.z)
            self.gravity = (g.x, g.y, g.z)
            if s != self.state { self.state = s }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        state = .tilted
    }

    deinit { manager.stopDeviceMotionUpdates() }
}
