import Foundation
import UIKit
import CoreGraphics

class HistoryManager: ObservableObject {
    static let shared = HistoryManager()

    static var historyDirectory: URL {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return URL(fileURLWithPath: NSTemporaryDirectory())
        }
        let dir = docs.appendingPathComponent("ScanHistory", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Published var items: [HistoryItem] = []

    private init() {
        loadItems()
    }

    func save(image: CGImage, detections: [Detection], text: String) {
        let id = UUID()
        let imageFileName = "\(id.uuidString).jpg"
        let imagePath = Self.historyDirectory.appendingPathComponent(imageFileName)

        // Save image as JPEG
        let uiImage = UIImage(cgImage: image)
        if let data = uiImage.jpegData(compressionQuality: 0.8) {
            try? data.write(to: imagePath)
        }

        let item = HistoryItem(
            id: id,
            date: Date(),
            text: text,
            detections: detections,
            imageFileName: imageFileName
        )

        // Save JSON
        let jsonPath = Self.historyDirectory.appendingPathComponent("\(id.uuidString).json")
        if let data = try? JSONEncoder().encode(item) {
            try? data.write(to: jsonPath)
        }

        DispatchQueue.main.async {
            self.items.insert(item, at: 0)
        }
    }

    func loadItems() {
        let dir = Self.historyDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }

        let jsonFiles = files.filter { $0.pathExtension == "json" }
        var loaded: [HistoryItem] = []

        for file in jsonFiles {
            if let data = try? Data(contentsOf: file),
               let item = try? JSONDecoder().decode(HistoryItem.self, from: data) {
                loaded.append(item)
            }
        }

        items = loaded.sorted { $0.date > $1.date }
    }

    func delete(item: HistoryItem) {
        let jsonPath = Self.historyDirectory.appendingPathComponent("\(item.id.uuidString).json")
        let imagePath = item.imagePath
        try? FileManager.default.removeItem(at: jsonPath)
        try? FileManager.default.removeItem(at: imagePath)
        items.removeAll { $0.id == item.id }
    }

    func updateTranslation(for itemID: UUID, translatedText: String) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].translatedText = translatedText

        // Re-save JSON
        let jsonPath = Self.historyDirectory.appendingPathComponent("\(itemID.uuidString).json")
        if let data = try? JSONEncoder().encode(items[index]) {
            try? data.write(to: jsonPath)
        }
    }

    func deleteAll() {
        for item in items {
            let jsonPath = Self.historyDirectory.appendingPathComponent("\(item.id.uuidString).json")
            try? FileManager.default.removeItem(at: jsonPath)
            try? FileManager.default.removeItem(at: item.imagePath)
        }
        items.removeAll()
    }
}
