import XCTest
import SwiftUI
import UIKit
import Combine
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

    func testSideHandleChangesOnlyOneDimension() {
        let start = CGRect(x: 100, y: 100, width: 40, height: 300)
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let wider = BoxEditGeometry.resized(start, corner: .right, by: CGSize(width: 25, height: 80), within: bounds)
        XCTAssertEqual(wider, CGRect(x: 100, y: 100, width: 65, height: 300))
        let shorter = BoxEditGeometry.resized(start, corner: .top, by: CGSize(width: -30, height: 50), within: bounds)
        XCTAssertEqual(shorter, CGRect(x: 100, y: 150, width: 40, height: 250))
    }

    func testHitHandleOnThinVerticalLine() {
        // A 20 pt wide, 300 pt tall line, as on an iPhone showing a whole page.
        let rect = CGRect(x: 100, y: 100, width: 20, height: 300)
        // Along the long sides, anywhere (not only at the middle), a little outside counts too.
        XCTAssertEqual(BoxEditGeometry.hitHandle(at: CGPoint(x: 92, y: 180), of: rect), .left)
        XCTAssertEqual(BoxEditGeometry.hitHandle(at: CGPoint(x: 130, y: 330), of: rect), .right)
        // The top side is not hidden by the two top corners 10 pt away.
        XCTAssertEqual(BoxEditGeometry.hitHandle(at: CGPoint(x: 110, y: 96), of: rect), .top)
        // Right on a corner, the corner wins.
        XCTAssertEqual(BoxEditGeometry.hitHandle(at: CGPoint(x: 121, y: 401), of: rect), .bottomRight)
        // The middle of the line is left for moving it.
        XCTAssertNil(BoxEditGeometry.hitHandle(at: CGPoint(x: 110, y: 250), of: rect))
        // Far away: nothing.
        XCTAssertNil(BoxEditGeometry.hitHandle(at: CGPoint(x: 160, y: 250), of: rect))
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

/// Guards for the problems reported on 2026-11-02 after 2.1 (box editing on an iPhone):
/// every box was the same 朱, a box could only be resized from its corners, brushing a
/// neighbour dragged it away, and dragging rebuilt the whole result screen so the box lagged.
@MainActor
final class BoxEditRegressionTests: XCTestCase {

    // MARK: Colours

    func testNeighbouringLinesNeverShareAColour() {
        let distinct = Set(KotenColor.boxPalette.map { UIColor($0).description })
        XCTAssertGreaterThanOrEqual(distinct.count, 3, "boxes must not all be one colour")
        for i in 0..<40 {
            XCTAssertNotEqual(UIColor(KotenColor.box(i)).description, UIColor(KotenColor.box(i + 1)).description,
                              "line \(i + 1) and \(i + 2) share a colour")
        }
        XCTAssertNotEqual(UIColor(KotenColor.box(0)).description, UIColor(KotenColor.box(2)).description)
    }

    // MARK: What a touch grabs

    /// Three touching vertical lines on a whole page on an iPhone: 20 pt wide, 300 pt tall.
    private let stage = BoxEditGeometry.Stage(size: CGSize(width: 100, height: 400),
                                              imageSize: CGSize(width: 100, height: 400), zoom: 1, offset: .zero)
    private let lines = [CGRect(x: 20, y: 50, width: 20, height: 300),
                         CGRect(x: 40, y: 50, width: 20, height: 300),
                         CGRect(x: 60, y: 50, width: 20, height: 300)]

    func testTouchingAnUnselectedBoxDoesNotMoveIt() {
        // Middle line selected; a finger well inside the right-hand neighbour.
        XCTAssertEqual(BoxEditGeometry.grab(at: CGPoint(x: 75, y: 200), stage: stage, rects: lines, selected: 1), .panOrSelect)
        // Nothing selected: touching a box never moves it either.
        XCTAssertEqual(BoxEditGeometry.grab(at: CGPoint(x: 50, y: 200), stage: stage, rects: lines, selected: nil), .panOrSelect)
    }

    func testSidesOfAThinLineResizeOnlyItsWidth() {
        XCTAssertEqual(BoxEditGeometry.grab(at: CGPoint(x: 41, y: 120), stage: stage, rects: lines, selected: 1), .resize(1, .left))
        XCTAssertEqual(BoxEditGeometry.grab(at: CGPoint(x: 62, y: 300), stage: stage, rects: lines, selected: 1), .resize(1, .right))
        XCTAssertEqual(BoxEditGeometry.grab(at: CGPoint(x: 50, y: 48), stage: stage, rects: lines, selected: 1), .resize(1, .top))
        XCTAssertEqual(BoxEditGeometry.grab(at: CGPoint(x: 50, y: 200), stage: stage, rects: lines, selected: 1), .move(1))
        let r = BoxEditGeometry.resized(lines[1], corner: .right, by: CGSize(width: 6, height: 40),
                                        within: CGRect(x: 0, y: 0, width: 100, height: 400))
        XCTAssertEqual(r.height, lines[1].height, "dragging a side must not change the other dimension")
        XCTAssertEqual(r.width, 26)
    }

    func testGripsStayFingerSizedWhenZoomedIn() {
        // At 3x the selected line is 60 pt wide; a side 15 pt outside it still counts.
        let zoomed = BoxEditGeometry.Stage(size: stage.size, imageSize: stage.imageSize, zoom: 3, offset: .zero)
        let right = zoomed.toStage(lines[1]).maxX
        let y = zoomed.toStage(CGPoint(x: 0, y: 180)).y
        XCTAssertEqual(BoxEditGeometry.grab(at: CGPoint(x: right + 15, y: y), stage: zoomed, rects: lines, selected: 1), .resize(1, .right))
    }

    // MARK: Smooth dragging

    func testDraggingDoesNotRebuildTheResultScreen() {
        let model = BoxEditModel()
        model.begin(detections: [Detection(box: [20, 50, 40, 350], score: 0.9, classId: 0, className: "line")],
                    imageSize: CGSize(width: 100, height: 400), selected: 0)
        var screenRebuilds = 0, canvasRedraws = 0
        let a = model.objectWillChange.sink { screenRebuilds += 1 }
        let b = model.drag.objectWillChange.sink { canvasRedraws += 1 }
        for i in 0..<30 {
            model.preview = .init(index: 0, rect: CGRect(x: 20 + Double(i), y: 50, width: 20, height: 300))
        }
        XCTAssertEqual(screenRebuilds, 0, "a finger move must not invalidate the whole result screen")
        XCTAssertEqual(canvasRedraws, 30)
        a.cancel(); b.cancel()
    }
}
