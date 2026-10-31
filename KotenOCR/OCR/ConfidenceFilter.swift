import Foundation

extension Detection {
    /// A line the reader has touched (moved, resized, split, merged, added, or its text edited) is
    /// certain by definition: it gets the top score so the confidence slider never hides it.
    mutating func markReaderConfirmed() { score = 1.0 }
}

/// The result screen's confidence slider. A display filter only: nothing is re-read and the stored
/// lines are never changed by moving the slider.
///
/// Scale note: both detectors give a sigmoid-style 0-1 score, but they are not calibrated against each
/// other. The classical detector (RTMDet) already drops scores under 0.3 and the modern one (DEIM) drops
/// 0.25 and below, so a line on screen never scores under those floors. The initial value 0.3 is the same
/// for both: it hides nothing in classical mode and only the 0.25-0.3 band in modern mode.
enum ConfidenceFilter {
    /// Classical mode's detector floor; also the initial slider value.
    static let defaultThreshold: Float = 0.3
    static let range: ClosedRange<Float> = 0.25...0.9

    /// Lines at or above `threshold`, each with its index in the full list. A score of exactly the
    /// threshold stays visible.
    static func visible(_ detections: [Detection], threshold: Float) -> [(index: Int, detection: Detection)] {
        detections.enumerated().compactMap { $0.element.score >= threshold ? ($0.offset, $0.element) : nil }
    }

    /// The text of the visible lines, one per line; empty lines are skipped.
    static func text(_ detections: [Detection], threshold: Float) -> String {
        visible(detections, threshold: threshold).map(\.detection.text).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    static func percentText(_ value: Float) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
