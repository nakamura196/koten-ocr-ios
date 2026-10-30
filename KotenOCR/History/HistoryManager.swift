import Foundation
import UIKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

class HistoryManager: ObservableObject {
    static let shared = HistoryManager()

    static let thumbnailMaxPixel: CGFloat = 200

    static var historyDirectory: URL {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return URL(fileURLWithPath: NSTemporaryDirectory())
        }
        let dir = docs.appendingPathComponent("ScanHistory", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Published var items: [HistoryItem] = []

    /// Directory this instance reads and writes (injectable for tests).
    let directory: URL

    /// Serial queue for all disk writes, so a delete can never race a pending save.
    private let ioQueue = DispatchQueue(label: "com.nakamura196.kotenocr.history-io", qos: .userInitiated)

    private convenience init() {
        self.init(directory: Self.historyDirectory)
    }

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        loadItems()
    }

    /// Blocks until all queued disk writes have finished (for tests).
    func flush() {
        ioQueue.sync {}
    }

    private func jsonURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    func imageURL(for item: HistoryItem) -> URL {
        directory.appendingPathComponent(item.imageFileName)
    }

    func thumbnailURL(for item: HistoryItem) -> URL {
        directory.appendingPathComponent(item.thumbnailFileName)
    }

    private func onMain(_ block: () -> Void) {
        if Thread.isMainThread { block() } else { DispatchQueue.main.sync(execute: block) }
    }

    /// Adds the item to the list immediately and returns its id.
    /// JPEG encoding, thumbnail generation and file writes happen on a background queue.
    @discardableResult
    func save(image: CGImage, detections: [Detection], text: String) -> UUID {
        let id = UUID()
        let imageFileName = "\(id.uuidString).jpg"
        let item = HistoryItem(
            id: id,
            date: Date(),
            text: text,
            detections: detections,
            imageFileName: imageFileName
        )
        onMain { items.insert(item, at: 0) }

        let imagePath = imageURL(for: item)
        let thumbPath = thumbnailURL(for: item)
        let jsonPath = jsonURL(for: id)
        // Ask iOS for a little extra time so the files are complete if the user leaves the app right
        // after a scan. (A swipe-away kill cannot be intercepted; there the entry is simply not saved.)
        let bgTask = UIApplication.shared.beginBackgroundTask(withName: "history-save")
        ioQueue.async {
            // Order matters: the JSON record goes last, so a record never points at a missing image.
            // Atomic writes (temp file + rename) mean a kill mid-write cannot leave a half-written file.
            if let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.8) {
                try? data.write(to: imagePath, options: .atomic)
                if let thumb = Self.makeThumbnailJPEG(from: data) {
                    try? thumb.write(to: thumbPath, options: .atomic)
                }
            }
            if let data = try? JSONEncoder().encode(item) {
                try? data.write(to: jsonPath, options: .atomic)
            }
            if bgTask != .invalid {
                DispatchQueue.main.async { UIApplication.shared.endBackgroundTask(bgTask) }
            }
        }
        return id
    }

    func loadItems() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }

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
        let urls = [jsonURL(for: item.id), imageURL(for: item), thumbnailURL(for: item)]
        ioQueue.async { urls.forEach { try? FileManager.default.removeItem(at: $0) } }
        items.removeAll { $0.id == item.id }
    }

    func updateTranslation(for itemID: UUID, translatedText: String) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].translatedText = translatedText
        persist(items[index])
    }

    /// Stores manual text edits. `text` is rebuilt from the detections (non-empty lines joined by newline).
    func updateDetections(id itemID: UUID, detections: [Detection]) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].detections = detections
        items[index].text = Self.combinedText(of: detections)
        persist(items[index])
    }

    static func combinedText(of detections: [Detection]) -> String {
        detections.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private func persist(_ item: HistoryItem) {
        let jsonPath = jsonURL(for: item.id)
        ioQueue.async {
            if let data = try? JSONEncoder().encode(item) {
                try? data.write(to: jsonPath, options: .atomic)
            }
        }
    }

    func deleteAll() {
        let urls = items.flatMap { [jsonURL(for: $0.id), imageURL(for: $0), thumbnailURL(for: $0)] }
        ioQueue.async { urls.forEach { try? FileManager.default.removeItem(at: $0) } }
        items.removeAll()
    }

    // MARK: - Thumbnails

    /// Downsamples encoded image data to a JPEG whose longer side is `maxPixel` (ImageIO, no full decode).
    static func makeThumbnailJPEG(from data: Data, maxPixel: CGFloat = thumbnailMaxPixel) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return thumbnailJPEG(from: source, maxPixel: maxPixel)
    }

    static func makeThumbnailJPEG(fromFile url: URL, maxPixel: CGFloat = thumbnailMaxPixel) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return thumbnailJPEG(from: source, maxPixel: maxPixel)
    }

    private static func thumbnailJPEG(from source: CGImageSource, maxPixel: CGFloat) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: 0.7)
    }

    /// Downsamples the original to `maxPixel` for a larger tile (home with one or two scans).
    /// Not stored; falls back to the list thumbnail.
    func preview(for item: HistoryItem, maxPixel: CGFloat) async -> UIImage? {
        let imagePath = imageURL(for: item)
        let image: UIImage? = await withCheckedContinuation { cont in
            ioQueue.async {
                cont.resume(returning: Self.makeThumbnailJPEG(fromFile: imagePath, maxPixel: maxPixel).flatMap(UIImage.init(data:)))
            }
        }
        if let image { return image }
        return await thumbnail(for: item)
    }

    /// Returns the list thumbnail. Uses the stored thumbnail if present; otherwise downsamples the
    /// original on a background thread and stores the result for next time (old items).
    func thumbnail(for item: HistoryItem) async -> UIImage? {
        let thumbPath = thumbnailURL(for: item)
        let imagePath = imageURL(for: item)
        return await withCheckedContinuation { cont in
            ioQueue.async {
                if let data = try? Data(contentsOf: thumbPath), let img = UIImage(data: data) {
                    cont.resume(returning: img)
                    return
                }
                guard let data = Self.makeThumbnailJPEG(fromFile: imagePath) else {
                    cont.resume(returning: nil)
                    return
                }
                try? data.write(to: thumbPath, options: .atomic)
                cont.resume(returning: UIImage(data: data))
            }
        }
    }
}
