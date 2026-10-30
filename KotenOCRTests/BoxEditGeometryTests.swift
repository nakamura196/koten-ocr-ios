import XCTest
@testable import KotenOCR

final class BoxEditGeometryTests: XCTestCase {

    private let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)

    // MARK: Move

    func testMoveUsesCumulativeTranslationFromStart() {
        let start = CGRect(x: 100, y: 100, width: 50, height: 80)
        var r = start
        for dx in [5.0, 15.0, 40.0] {   // cumulative values reported by one drag
            r = BoxEditGeometry.moved(start, by: CGSize(width: dx, height: 0), within: bounds)
        }
        XCTAssertEqual(r.minX, 140, accuracy: 0.001)
    }

    func testMoveClampsToImage() {
        let start = CGRect(x: 100, y: 100, width: 50, height: 80)
        let r = BoxEditGeometry.moved(start, by: CGSize(width: -999, height: 999), within: bounds)
        XCTAssertEqual(r.minX, 0, accuracy: 0.001)
        XCTAssertEqual(r.maxY, 300, accuracy: 0.001)
        XCTAssertEqual(r.size, start.size)
    }

    // MARK: Resize

    func testResizeBottomRightKeepsOppositeCorner() {
        let start = CGRect(x: 100, y: 100, width: 50, height: 80)
        let r = BoxEditGeometry.resized(start, corner: .bottomRight, by: CGSize(width: 20, height: 10), within: bounds)
        XCTAssertEqual(r, CGRect(x: 100, y: 100, width: 70, height: 90))
    }

    func testResizeTopLeftKeepsOppositeCorner() {
        let start = CGRect(x: 100, y: 100, width: 50, height: 80)
        let r = BoxEditGeometry.resized(start, corner: .topLeft, by: CGSize(width: -30, height: -10), within: bounds)
        XCTAssertEqual(r.maxX, 150, accuracy: 0.001)
        XCTAssertEqual(r.maxY, 180, accuracy: 0.001)
        XCTAssertEqual(r.minX, 70, accuracy: 0.001)
        XCTAssertEqual(r.minY, 90, accuracy: 0.001)
    }

    func testResizeIsClampedToImage() {
        let start = CGRect(x: 100, y: 100, width: 50, height: 80)
        let r = BoxEditGeometry.resized(start, corner: .bottomRight, by: CGSize(width: 9999, height: 9999), within: bounds)
        XCTAssertEqual(r.maxX, 400, accuracy: 0.001)
        XCTAssertEqual(r.maxY, 300, accuracy: 0.001)
        let r2 = BoxEditGeometry.resized(start, corner: .topLeft, by: CGSize(width: -9999, height: -9999), within: bounds)
        XCTAssertEqual(r2.minX, 0, accuracy: 0.001)
        XCTAssertEqual(r2.minY, 0, accuracy: 0.001)
    }

    func testResizeNeverGoesBelowMinimumSize() {
        let start = CGRect(x: 100, y: 100, width: 50, height: 80)
        let r = BoxEditGeometry.resized(start, corner: .bottomRight, by: CGSize(width: -999, height: -999), within: bounds)
        XCTAssertEqual(r.width, BoxEditGeometry.minSide, accuracy: 0.001)
        XCTAssertEqual(r.height, BoxEditGeometry.minSide, accuracy: 0.001)
        XCTAssertEqual(r.minX, 100, accuracy: 0.001)   // the opposite corner did not move
        let r2 = BoxEditGeometry.resized(start, corner: .topLeft, by: CGSize(width: 999, height: 999), within: bounds)
        XCTAssertEqual(r2.maxX, 150, accuracy: 0.001)
        XCTAssertEqual(r2.width, BoxEditGeometry.minSide, accuracy: 0.001)
    }

    // MARK: Draw

    func testDrawnNormalisesAndClamps() throws {
        let r = try XCTUnwrap(BoxEditGeometry.drawn(from: CGPoint(x: 300, y: 200), to: CGPoint(x: 500, y: 100), within: bounds))
        XCTAssertEqual(r, CGRect(x: 300, y: 100, width: 100, height: 100))
    }

    func testDrawnTooSmallIsNil() {
        XCTAssertNil(BoxEditGeometry.drawn(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 15, y: 90), within: bounds))
    }

    // MARK: Split and merge

    func testSplitTallBoxCutsAcrossTheColumn() throws {
        let box = CGRect(x: 100, y: 50, width: 40, height: 200)
        let (a, b) = try XCTUnwrap(BoxEditGeometry.split(box, at: CGPoint(x: 120, y: 120)))
        XCTAssertEqual(a, CGRect(x: 100, y: 50, width: 40, height: 70))
        XCTAssertEqual(b, CGRect(x: 100, y: 120, width: 40, height: 130))
    }

    func testSplitWideBoxCutsDownTheMiddle() throws {
        let box = CGRect(x: 0, y: 0, width: 200, height: 40)
        let (a, b) = try XCTUnwrap(BoxEditGeometry.split(box, at: CGPoint(x: 60, y: 20)))
        XCTAssertEqual(a, CGRect(x: 0, y: 0, width: 60, height: 40))
        XCTAssertEqual(b, CGRect(x: 60, y: 0, width: 140, height: 40))
    }

    func testSplitRejectsOutsideOrTooCloseToEdge() {
        let box = CGRect(x: 100, y: 50, width: 40, height: 200)
        XCTAssertNil(BoxEditGeometry.split(box, at: CGPoint(x: 10, y: 10)))
        XCTAssertNil(BoxEditGeometry.split(box, at: CGPoint(x: 120, y: 52)))
        XCTAssertNil(BoxEditGeometry.split(box, at: CGPoint(x: 120, y: 249)))
    }

    func testMergeIsTheUnion() {
        let a = CGRect(x: 10, y: 10, width: 20, height: 100)
        let b = CGRect(x: 40, y: 0, width: 20, height: 90)
        XCTAssertEqual(BoxEditGeometry.merged(a, b), CGRect(x: 10, y: 0, width: 50, height: 110))
    }

    // MARK: Hit testing

    func testHitBoxPrefersTheSmallestOverlappingBox() {
        let rects = [CGRect(x: 0, y: 0, width: 100, height: 100), CGRect(x: 40, y: 40, width: 20, height: 20)]
        XCTAssertEqual(BoxEditGeometry.hitBox(at: CGPoint(x: 50, y: 50), in: rects), 1)
        XCTAssertEqual(BoxEditGeometry.hitBox(at: CGPoint(x: 5, y: 5), in: rects), 0)
        XCTAssertNil(BoxEditGeometry.hitBox(at: CGPoint(x: 200, y: 5), in: rects))
    }

    func testHitCornerWithinRadiusOnly() {
        let rect = CGRect(x: 100, y: 100, width: 50, height: 80)
        XCTAssertEqual(BoxEditGeometry.hitCorner(at: CGPoint(x: 148, y: 182), of: rect, radius: 22), .bottomRight)
        XCTAssertNil(BoxEditGeometry.hitCorner(at: CGPoint(x: 125, y: 140), of: rect, radius: 22))
    }

    // MARK: Stage mapping

    func testStageRoundTripAtZoomAndOffset() {
        let stage = BoxEditGeometry.Stage(size: CGSize(width: 400, height: 600), imageSize: CGSize(width: 2000, height: 1000),
                                          zoom: 2.5, offset: CGSize(width: -30, height: 45))
        let p = CGPoint(x: 700, y: 321)
        let back = stage.toImage(stage.toStage(p))
        XCTAssertEqual(back.x, p.x, accuracy: 0.01)
        XCTAssertEqual(back.y, p.y, accuracy: 0.01)
    }

    func testStageFitsImageAtZoomOne() {
        let stage = BoxEditGeometry.Stage(size: CGSize(width: 400, height: 600), imageSize: CGSize(width: 2000, height: 1000),
                                          zoom: 1, offset: .zero)
        XCTAssertEqual(stage.fit, CGRect(x: 0, y: 200, width: 400, height: 200))
        let origin = stage.toStage(CGPoint.zero)
        XCTAssertEqual(origin.x, 0, accuracy: 0.001)
        XCTAssertEqual(origin.y, 200, accuracy: 0.001)
        XCTAssertEqual(stage.pixelsPerPoint, 5, accuracy: 0.001)
    }
}
