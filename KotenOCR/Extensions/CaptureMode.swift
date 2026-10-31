import Foundation

/// Remembers whether the user last used the normal camera or the document scanner.
enum CaptureMode: String {
    case camera, scan

    static let defaultsKey = "lastCaptureMode"

    static func load(from defaults: UserDefaults = .standard) -> CaptureMode {
        defaults.string(forKey: defaultsKey).flatMap(CaptureMode.init(rawValue:)) ?? .camera
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}
