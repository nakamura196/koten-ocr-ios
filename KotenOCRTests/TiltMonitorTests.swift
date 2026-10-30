import XCTest
@testable import KotenOCR

final class TiltMonitorTests: XCTestCase {

    func testFlatFacingDown() {
        let s = TiltState.classify(x: 0, y: 0, z: -1)
        XCTAssertEqual(s, .flat(deviation: 0))
        XCTAssertFalse(s.showsHint)
    }

    func testFlatSlightlyOffShowsNoHintUnderThreshold() {
        let a = 5.0 * .pi / 180
        XCTAssertFalse(TiltState.classify(x: 0, y: sin(a), z: -cos(a)).showsHint)
    }

    func testFlatBeyondThresholdShowsHint() {
        let a = 15.0 * .pi / 180
        let s = TiltState.classify(x: 0, y: -sin(a), z: -cos(a))
        guard case .flat(let d) = s else { return XCTFail("expected flat, got \(s)") }
        XCTAssertEqual(d, 15, accuracy: 0.01)
        XCTAssertTrue(s.showsHint)
    }

    func testUprightPortrait() {
        let s = TiltState.classify(x: 0, y: -1, z: 0)
        XCTAssertEqual(s, .upright(deviation: 0))
        XCTAssertFalse(s.showsHint)
    }

    func testUprightLeaningShowsHint() {
        let a = 12.0 * .pi / 180
        let s = TiltState.classify(x: 0, y: -cos(a), z: -sin(a))
        guard case .upright = s else { return XCTFail("expected upright, got \(s)") }
        XCTAssertTrue(s.showsHint)
    }

    func testInBetweenAndFaceUpAreTilted() {
        let a = 55.0 * .pi / 180
        XCTAssertEqual(TiltState.classify(x: 0, y: -sin(a), z: -cos(a)), .tilted)
        XCTAssertEqual(TiltState.classify(x: 0, y: 0, z: 1), .tilted)   // camera pointing at the ceiling
        XCTAssertFalse(TiltState.tilted.showsHint)
    }

    func testZeroVectorIsTilted() {
        XCTAssertEqual(TiltState.classify(x: 0, y: 0, z: 0), .tilted)
    }
}

final class CaptureModeTests: XCTestCase {
    func testDefaultsToCameraThenRemembers() {
        let suite = "CaptureModeTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        XCTAssertEqual(CaptureMode.load(from: d), .camera)
        CaptureMode.scan.save(to: d)
        XCTAssertEqual(CaptureMode.load(from: d), .scan)
        CaptureMode.camera.save(to: d)
        XCTAssertEqual(CaptureMode.load(from: d), .camera)
    }

    func testGarbageValueFallsBackToCamera() {
        let suite = "CaptureModeTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        d.set("bogus", forKey: CaptureMode.defaultsKey)
        XCTAssertEqual(CaptureMode.load(from: d), .camera)
    }
}
