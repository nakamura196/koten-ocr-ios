import Foundation

struct HistoryItem: Codable, Identifiable {
    let id: UUID
    let date: Date
    var text: String
    var detections: [Detection]
    let imageFileName: String
    var translatedText: String?

    var imagePath: URL {
        HistoryManager.historyDirectory.appendingPathComponent(imageFileName)
    }

    /// Small JPEG used by the history list (generated at save time; may be missing for old items).
    var thumbnailFileName: String { "\(id.uuidString)_thumb.jpg" }
}
