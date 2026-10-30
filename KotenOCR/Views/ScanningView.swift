import SwiftUI

/// Processing screen (storyboard c): a 朱 beam sweeps right → left with the real progress,
/// then the found lines appear one by one in reading order before the result opens.
struct ScanningView: View {
    let image: CGImage
    /// OCR engine progress, 0...1.
    let progress: Float
    /// Lines to reveal once OCR has finished (empty while still processing).
    let detections: [Detection]
    /// How many of `detections` are shown so far.
    let revealedCount: Int
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private var finished: Bool { !detections.isEmpty }

    /// Beam position from the right edge, 0 (start) ... 1 (left edge). Recognition ends at 0.9.
    private var sweep: CGFloat { CGFloat(min(1, max(0, progress / 0.9))) }

    private var statusText: String {
        if finished {
            if revealedCount >= detections.count {
                return String(format: String(localized: "scan_done_format", defaultValue: "%d 行を読み取りました"), detections.count)
            }
            return String(localized: "scan_reading_text", defaultValue: "文字を読んでいます…")
        }
        if progress < 0.2 { return String(localized: "scan_preparing", defaultValue: "準備しています…") }
        if progress < 0.5 { return String(localized: "scan_finding_lines", defaultValue: "行を探しています…") }
        return String(localized: "scan_reading_text", defaultValue: "文字を読んでいます…")
    }

    var body: some View {
        VStack(spacing: 0) {
            navBar
                .padding(.horizontal, 14)
                .padding(.top, 6)

            documentView
                .kotenMount()
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .frame(maxHeight: typeSize.isAccessibilitySize ? 220 : 360)

            Spacer(minLength: 12)

            sheet
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
        }
        .washiBackground()
    }

    // MARK: - Parts

    private var navBar: some View {
        ZStack {
            Text(finished && revealedCount >= detections.count
                 ? String(format: String(localized: "lines_count_format", defaultValue: "%d 行"), detections.count)
                 : String(localized: "scan_title", defaultValue: "読み取り中"))
                .font(.mincho(18, relativeTo: .headline, bold: true))
                .foregroundColor(KotenColor.ink)
                .lineLimit(1)
                .padding(.horizontal, 100)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button(action: onCancel) {
                    Text(String(localized: "cancel", defaultValue: "Cancel"))
                        .font(.body.weight(.bold))
                        .padding(.horizontal, 18)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.kotenGlass)
                .accessibilityIdentifier("cancel_processing_button")
                Spacer()
            }
        }
    }

    private var documentView: some View {
        ZStack {
            // Not yet read: grey, slightly sepia.
            Image(decorative: image, scale: 1.0)
                .resizable()
                .scaledToFit()
                .grayscale(1)
                .colorMultiply(Color(red: 0.95, green: 0.9, blue: 0.82))
                .brightness(-0.05)
            // Already swept: full colour, revealed from the right.
            Image(decorative: image, scale: 1.0)
                .resizable()
                .scaledToFit()
                .mask(alignment: .trailing) {
                    GeometryReader { geo in
                        Rectangle()
                            .frame(width: geo.size.width * (finished ? 1 : sweep))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .overlay { overlayLayer }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(statusText))
    }

    private var overlayLayer: some View {
        GeometryReader { geo in
            let sx = image.width > 0 ? geo.size.width / CGFloat(image.width) : 0
            let sy = image.height > 0 ? geo.size.height / CGFloat(image.height) : 0
            ZStack(alignment: .topLeading) {
                if !finished && !reduceMotion {
                    beam(height: geo.size.height)
                        .position(x: geo.size.width * (1 - sweep), y: geo.size.height / 2)
                        .animation(.linear(duration: 0.4), value: sweep)
                }
                ForEach(Array(detections.prefix(revealedCount).enumerated()), id: \.offset) { index, det in
                    let rect = CGRect(x: CGFloat(det.box[0]) * sx, y: CGFloat(det.box[1]) * sy,
                                      width: CGFloat(det.box[2] - det.box[0]) * sx,
                                      height: CGFloat(det.box[3] - det.box[1]) * sy)
                    let isNewest = index == revealedCount - 1
                    Rectangle()
                        .fill(KotenColor.shu.opacity(isNewest ? 0.25 : 0.1))
                        .overlay(Rectangle().stroke(KotenColor.shu, lineWidth: isNewest ? 2.5 : 1.5))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .transition(reduceMotion ? .opacity : .scale(scale: 1.25).combined(with: .opacity))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func beam(height: CGFloat) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(KotenColor.shu)
                .frame(width: 3)
                .shadow(color: KotenColor.shu, radius: 6)
                .shadow(color: KotenColor.shu.opacity(0.6), radius: 18)
            // Faint tail behind the beam (towards the swept side, i.e. right).
            LinearGradient(colors: [KotenColor.shu.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 70)
        }
        .frame(height: height + 20)
        .offset(x: 35)
    }

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(statusText)
                    .font(.mincho(19, relativeTo: .headline, bold: true))
                    .foregroundColor(KotenColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if finished {
                    Text(String(format: String(localized: "lines_count_format", defaultValue: "%d 行"), revealedCount))
                        .font(.mincho(28, relativeTo: .title, bold: true))
                        .foregroundColor(KotenColor.shu)
                        .monospacedDigit()
                        .accessibilityHidden(true)
                }
            }
            ProgressView(value: finished
                         ? Double(revealedCount) / Double(max(detections.count, 1))
                         : Double(min(progress, 1)))
                .tint(KotenColor.shu)
                .accessibilityHidden(true)

            if finished {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(detections.prefix(revealedCount).enumerated().suffix(4)), id: \.offset) { index, det in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(KotenColor.shu)
                                .frame(minWidth: 18, alignment: .trailing)
                            Text(det.text)
                                .font(.mincho(17, relativeTo: .body))
                                .foregroundColor(KotenColor.ink)
                                .lineLimit(1)
                        }
                        .transition(KotenMotion.rise(8, reduceMotion: reduceMotion))
                    }
                }
                .accessibilityHidden(true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kotenGlass(.regular, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
    }
}
