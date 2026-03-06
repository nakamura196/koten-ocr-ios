import XCTest
@testable import KotenOCR

final class ExportManagerTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        // Cleanup temp files
        let tempDir = FileManager.default.temporaryDirectory
        try? FileManager.default.removeItem(at: tempDir.appendingPathComponent("TestExport.txt"))
        try? FileManager.default.removeItem(at: tempDir.appendingPathComponent("TestExport.pdf"))
    }

    // MARK: - TXT Export

    func testExportAsTXT() {
        let url = ExportManager.exportAsTXT(text: "テスト出力", fileName: "TestExport")
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.path.hasSuffix(".txt"))

        let content = try? String(contentsOf: url!, encoding: .utf8)
        XCTAssertEqual(content, "テスト出力")
    }

    func testExportAsTXTEmptyText() {
        let url = ExportManager.exportAsTXT(text: "", fileName: "TestExport")
        XCTAssertNotNil(url)

        let content = try? String(contentsOf: url!, encoding: .utf8)
        XCTAssertEqual(content, "")
    }

    func testExportAsTXTMultiline() {
        let text = "行1\n行2\n行3"
        let url = ExportManager.exportAsTXT(text: text, fileName: "TestExport")
        XCTAssertNotNil(url)

        let content = try? String(contentsOf: url!, encoding: .utf8)
        XCTAssertEqual(content, text)
    }

    // MARK: - PDF Export

    func testExportAsPDFWithTextOnly() {
        let url = ExportManager.exportAsPDF(text: "PDF出力テスト", image: nil, fileName: "TestExport")
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.path.hasSuffix(".pdf"))

        // Verify file exists and is non-empty
        let data = try? Data(contentsOf: url!)
        XCTAssertNotNil(data)
        XCTAssertGreaterThan(data!.count, 0)
    }

    func testExportAsPDFWithImage() {
        // Create a simple 10x10 CGImage
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: 10, height: 10,
            bitsPerComponent: 8, bytesPerRow: 40,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = ctx.makeImage() else {
            XCTFail("Failed to create test image")
            return
        }

        let url = ExportManager.exportAsPDF(text: "テスト", image: image, fileName: "TestExport")
        XCTAssertNotNil(url)

        let data = try? Data(contentsOf: url!)
        XCTAssertNotNil(data)
        XCTAssertGreaterThan(data!.count, 0)
    }
}
