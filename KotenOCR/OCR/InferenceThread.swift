import Foundation

/// One long-lived thread for the detection models.
///
/// ONNX Runtime's matrix code (MLAS) keeps a per-thread scratch buffer sized for the largest
/// layer that thread has run, and frees it only when the thread exits. Detection (RTMDet 1024 px,
/// DEIM 800 px) needs ~100 MB of it. Run from `Task.detached`, detection lands on a different
/// Swift-concurrency worker thread almost every time, and each of those threads kept its own
/// buffer: on the simulator the footprint rose by ~100 MB per image until every worker had one
/// (~1 GB after 5 images in NDL mode). Running detection always on this thread keeps one buffer.
final class InferenceThread: @unchecked Sendable {
    static let shared = InferenceThread()

    private let condition = NSCondition()
    private var jobs: [() -> Void] = []
    private var thread: Thread?

    init(name: String = "com.nakamura196.kotenocr.inference") {
        let t = Thread { [unowned self] in self.loop() }
        t.name = name
        t.qualityOfService = .userInitiated
        t.stackSize = 8 << 20
        thread = t
        t.start()
    }

    private func loop() {
        repeat {
            condition.lock()
            while jobs.isEmpty { condition.wait() }
            let job = jobs.removeFirst()
            condition.unlock()
            autoreleasepool { job() }
        } while true
    }

    /// Runs `body` on the inference thread and returns its result. Jobs run one at a time, in order.
    func run<T>(_ body: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<T, Error>) in
            condition.lock()
            jobs.append { cont.resume(with: Result { try body() }) }
            condition.signal()
            condition.unlock()
        }
    }
}
