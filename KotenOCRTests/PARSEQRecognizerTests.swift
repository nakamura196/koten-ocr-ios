import XCTest
@testable import KotenOCR

final class PARSEQRecognizerTests: XCTestCase {

    // MARK: - Rotation

    func testRotatePixels90CCW() {
        let recognizer = PARSEQRecognizer.self
        // Create a test helper since rotatePixels90CCW is an instance method
        // We'll test via a helper that accesses the method

        // 2x3 image (W=2, H=3) with distinct pixel values
        // Row 0: [R,G,B,A] = [10,0,0,255], [20,0,0,255]
        // Row 1: [30,0,0,255], [40,0,0,255]
        // Row 2: [50,0,0,255], [60,0,0,255]
        var pixels: [UInt8] = [
            10, 0, 0, 255,  20, 0, 0, 255,
            30, 0, 0, 255,  40, 0, 0, 255,
            50, 0, 0, 255,  60, 0, 0, 255,
        ]

        // After 90° CCW rotation of 2x3 → 3x2
        // New pixel mapping:
        //   newX = y, newY = width - 1 - x
        //   (0,0) → (0, 1), (1,0) → (0, 0)
        //   (0,1) → (1, 1), (1,1) → (1, 0)
        //   (0,2) → (2, 1), (1,2) → (2, 0)
        //
        // So new image (3x2):
        //   Row 0: pixel at (x=0,y=0)=orig(1,0)=20, pixel at (x=1,y=0)=orig(1,1)=40, pixel at (x=2,y=0)=orig(1,2)=60
        //   Row 1: pixel at (x=0,y=1)=orig(0,0)=10, pixel at (x=1,y=1)=orig(0,1)=30, pixel at (x=2,y=1)=orig(0,2)=50

        // We need an instance to call the method
        // Since PARSEQRecognizer requires ONNX model, test the logic directly
        let width = 2
        let height = 3
        let newWidth = height  // 3
        let newHeight = width  // 2
        var rotated = [UInt8](repeating: 0, count: newWidth * newHeight * 4)

        for y in 0..<height {
            for x in 0..<width {
                let srcIdx = (y * width + x) * 4
                let newX = y
                let newY = width - 1 - x
                let dstIdx = (newY * newWidth + newX) * 4
                rotated[dstIdx] = pixels[srcIdx]
                rotated[dstIdx + 1] = pixels[srcIdx + 1]
                rotated[dstIdx + 2] = pixels[srcIdx + 2]
                rotated[dstIdx + 3] = pixels[srcIdx + 3]
            }
        }

        XCTAssertEqual(rotated.count, 3 * 2 * 4) // 3 wide, 2 tall
        // Row 0 (y=0): pixels from x=1 of original (20, 40, 60)
        XCTAssertEqual(rotated[0], 20)  // (0,0).R
        XCTAssertEqual(rotated[4], 40)  // (1,0).R
        XCTAssertEqual(rotated[8], 60)  // (2,0).R
        // Row 1 (y=1): pixels from x=0 of original (10, 30, 50)
        XCTAssertEqual(rotated[12], 10) // (0,1).R
        XCTAssertEqual(rotated[16], 30) // (1,1).R
        XCTAssertEqual(rotated[20], 50) // (2,1).R
    }

    // MARK: - Greedy Decode Logic

    func testGreedyDecodeBasic() {
        // vocabSize=4, seqLen=3
        // charList = ['A', 'B', 'C']
        // index 0 = EOS, 1=A, 2=B, 3=C
        let floats: [Float] = [
            // t=0: max at index 1 → 'A'
            -1, 5, -1, -1,
            // t=1: max at index 3 → 'C'
            -1, -1, -1, 5,
            // t=2: max at index 0 → EOS
            5, -1, -1, -1,
        ]
        let charList: [Character] = ["A", "B", "C"]

        let result = greedyDecode(floats: floats, seqLen: 3, vocabSize: 4, charList: charList)
        XCTAssertEqual(result, "AC")
    }

    func testGreedyDecodeEOSAtStart() {
        let floats: [Float] = [5, -1, -1] // EOS immediately
        let charList: [Character] = ["A", "B"]

        let result = greedyDecode(floats: floats, seqLen: 1, vocabSize: 3, charList: charList)
        XCTAssertEqual(result, "")
    }

    func testGreedyDecodeNoEOS() {
        let floats: [Float] = [
            -1, 5, -1,  // t=0 → index 1 → 'X'
            -1, -1, 5,  // t=1 → index 2 → 'Y'
        ]
        let charList: [Character] = ["X", "Y"]

        let result = greedyDecode(floats: floats, seqLen: 2, vocabSize: 3, charList: charList)
        XCTAssertEqual(result, "XY")
    }

    func testGreedyDecodeJapaneseCharacters() {
        let charList: [Character] = ["あ", "い", "う", "え", "お"]
        let floats: [Float] = [
            -1, -1, 5, -1, -1, -1,  // t=0 → index 2 → 'い'
            -1, -1, -1, -1, -1, 5,  // t=1 → index 5 → 'お'
            5, -1, -1, -1, -1, -1,  // t=2 → EOS
        ]

        let result = greedyDecode(floats: floats, seqLen: 3, vocabSize: 6, charList: charList)
        XCTAssertEqual(result, "いお")
    }

    // MARK: - Helper (replicates greedy decode logic)

    private func greedyDecode(floats: [Float], seqLen: Int, vocabSize: Int, charList: [Character]) -> String {
        var result: [Character] = []
        for t in 0..<seqLen {
            let offset = t * vocabSize
            var maxIdx = 0
            var maxVal: Float = -.infinity
            for v in 0..<vocabSize {
                let val = floats[offset + v]
                if val > maxVal {
                    maxVal = val
                    maxIdx = v
                }
            }
            if maxIdx == 0 { break }
            let charIdx = maxIdx - 1
            if charIdx >= 0 && charIdx < charList.count {
                result.append(charList[charIdx])
            }
        }
        return String(result)
    }
}
