import Foundation
import MetricKit

/// Collects crash diagnostics and performance metrics via MetricKit.
/// Reports are delivered by the system approximately once per day.
final class MetricKitManager: NSObject, MXMetricManagerSubscriber {
    static let shared = MetricKitManager()

    private override init() {
        super.init()
    }

    func start() {
        MXMetricManager.shared.add(self)
    }

    // MARK: - MXMetricManagerSubscriber

    /// Called ~once per day with aggregated metrics
    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            let json = payload.jsonRepresentation()
            saveReport(json, prefix: "metric")
        }
    }

    /// Called when a crash or diagnostic report is available
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let json = payload.jsonRepresentation()
            saveReport(json, prefix: "diagnostic")

            // Log crash info
            if let crashDiagnostics = payload.crashDiagnostics {
                for crash in crashDiagnostics {
                    let reason = crash.terminationReason ?? "unknown"
                    let signal = crash.signal?.intValue ?? -1
                    print("[MetricKit] Crash: signal=\(signal) reason=\(reason)")
                    print("[MetricKit] Stack: \(crash.callStackTree.jsonRepresentation())")
                }
            }

            if let hangDiagnostics = payload.hangDiagnostics {
                for hang in hangDiagnostics {
                    print("[MetricKit] Hang: duration=\(hang.hangDuration)")
                }
            }
        }
    }

    // MARK: - Save to Documents

    private func saveReport(_ json: Data, prefix: String) {
        let dir = getReportsDirectory()
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let filename = "\(prefix)_\(timestamp).json"
        let url = dir.appendingPathComponent(filename)

        do {
            try json.write(to: url)
            print("[MetricKit] Saved \(prefix) report: \(filename)")
        } catch {
            print("[MetricKit] Failed to save report: \(error)")
        }
    }

    private func getReportsDirectory() -> URL {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return URL(fileURLWithPath: NSTemporaryDirectory()) }
        let dir = docs.appendingPathComponent("MetricKitReports")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Return all saved reports for debugging/export
    func getSavedReports() -> [(filename: String, data: Data)] {
        let dir = getReportsDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        return files.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return (url.lastPathComponent, data)
        }
    }
}
