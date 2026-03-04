import Foundation

struct HistoryItem: Codable, Identifiable {
    let id: UUID
    let date: Date
    let text: String
    let detections: [Detection]
    let imageFileName: String

    var imagePath: URL {
        HistoryManager.historyDirectory.appendingPathComponent(imageFileName)
    }
}
