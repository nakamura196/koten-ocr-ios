import XCTest
import UIKit
@testable import KotenOCR

final class HistoryManagerTests: XCTestCase {

    private var dir: URL!
    private var manager: HistoryManager!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("HistoryManagerTests-\(UUID().uuidString)")
        manager = HistoryManager(directory: dir)
    }

    override func tearDown() {
        manager.flush()
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func makeImage(width: Int = 800, height: Int = 600) -> CGImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height),
                                               format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        return renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }.cgImage!
    }

    private func det(_ text: String) -> Detection {
        Detection(box: [0, 0, 10, 10], score: 0.9, classId: 0, className: "text", text: text)
    }

    func testSaveReturnsIdOfInsertedItem() {
        let first = manager.save(image: makeImage(), detections: [det("一")], text: "一")
        let second = manager.save(image: makeImage(), detections: [det("二")], text: "二")
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(manager.items.first?.id, second)
        XCTAssertEqual(manager.items.map(\.id), [second, first])
    }

    func testTranslationGoesToSavedItemNotNewest() {
        let first = manager.save(image: makeImage(), detections: [det("一")], text: "一")
        // A newer item exists; the translation for `first` must not land on it.
        let second = manager.save(image: makeImage(), detections: [det("二")], text: "二")
        manager.updateTranslation(for: first, translatedText: "one")
        XCTAssertEqual(manager.items.first { $0.id == first }?.translatedText, "one")
        XCTAssertNil(manager.items.first { $0.id == second }?.translatedText)
        manager.flush()
        let reloaded = HistoryManager(directory: dir)
        XCTAssertEqual(reloaded.items.first { $0.id == first }?.translatedText, "one")
    }

    func testUpdateDetectionsRewritesTextAndPersists() {
        let id = manager.save(image: makeImage(), detections: [det("あ"), det("い")], text: "あ\nい")
        manager.updateDetections(id: id, detections: [det("あ"), det("修正"), det("")])
        XCTAssertEqual(manager.items.first?.text, "あ\n修正")
        XCTAssertEqual(manager.items.first?.detections.map(\.text), ["あ", "修正", ""])
        manager.flush()
        let reloaded = HistoryManager(directory: dir)
        XCTAssertEqual(reloaded.items.first?.text, "あ\n修正")
        XCTAssertEqual(reloaded.items.first?.detections[1].text, "修正")
    }

    func testFilesAndThumbnailAreWritten() throws {
        let id = manager.save(image: makeImage(), detections: [], text: "")
        manager.flush()
        let item = try XCTUnwrap(manager.items.first { $0.id == id })
        XCTAssertTrue(FileManager.default.fileExists(atPath: manager.imageURL(for: item).path))
        let thumbData = try Data(contentsOf: manager.thumbnailURL(for: item))
        let thumb = try XCTUnwrap(UIImage(data: thumbData))
        XCTAssertLessThanOrEqual(max(thumb.size.width * thumb.scale, thumb.size.height * thumb.scale), 200)
    }

    func testDeleteRemovesAllFiles() throws {
        let id = manager.save(image: makeImage(), detections: [], text: "")
        manager.flush()
        let item = try XCTUnwrap(manager.items.first { $0.id == id })
        manager.delete(item: item)
        manager.flush()
        XCTAssertTrue(manager.items.isEmpty)
        let remaining = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(remaining.isEmpty, "left over: \(remaining)")
    }

    func testThumbnailDownsamplesAndKeepsAspect() throws {
        let jpeg = try XCTUnwrap(UIImage(cgImage: makeImage(width: 2000, height: 1000)).jpegData(compressionQuality: 0.9))
        let thumbData = try XCTUnwrap(HistoryManager.makeThumbnailJPEG(from: jpeg))
        let thumb = try XCTUnwrap(UIImage(data: thumbData)?.cgImage)
        XCTAssertEqual(thumb.width, 200)
        XCTAssertEqual(thumb.height, 100)
    }

    func testThumbnailFallbackForOldItemWithoutThumbFile() async throws {
        let id = manager.save(image: makeImage(width: 1200, height: 1200), detections: [], text: "")
        manager.flush()
        let item = try XCTUnwrap(manager.items.first { $0.id == id })
        try FileManager.default.removeItem(at: manager.thumbnailURL(for: item))
        let img = await manager.thumbnail(for: item)
        let thumb = try XCTUnwrap(img?.cgImage)
        XCTAssertLessThanOrEqual(max(thumb.width, thumb.height), 200)
        XCTAssertTrue(FileManager.default.fileExists(atPath: manager.thumbnailURL(for: item).path))
    }

    func testAccessibilityLabelContainsDateAndFirstLine() {
        let item = HistoryItem(id: UUID(), date: Date(timeIntervalSince1970: 1718430600), text: "第一行\n第二行",
                               detections: [], imageFileName: "x.jpg")
        let label = HistoryListView.accessibilityLabel(for: item, locale: Locale(identifier: "en_US"))
        XCTAssertTrue(label.contains("第一行"))
        XCTAssertFalse(label.contains("第二行"))
        XCTAssertTrue(label.contains("2024"))
    }
}
