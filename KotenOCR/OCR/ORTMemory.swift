import Foundation
import OnnxRuntimeBindings

/// ONNX Runtime keeps the CPU memory it grew for a run (its "arena") and never gives it back.
/// Recognition runs four crops at a time on each session, so every session's arena grows to fit
/// four runs, and with both OCR modes used the app held over 1.3 GB on the simulator after two
/// images (see MemoryRegressionTests). Shrinking the arena at the end of each run returns that memory.
enum ORTMemory {
    static let shrinkArenaKey = "memory.enable_memory_arena_shrinkage"

    static func runOptions() -> ORTRunOptions? {
        guard let options = try? ORTRunOptions() else { return nil }
        try? options.addConfigEntry(withKey: shrinkArenaKey, value: "cpu:0")
        return options
    }
}
