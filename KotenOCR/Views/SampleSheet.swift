import SwiftUI
import ImageIO

/// A page bundled with the app, so the reader can try OCR without a book at hand.
struct SamplePage: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let credit: LocalizedStringKey
    let mode: OCRMode

    static let all: [SamplePage] = [
        SamplePage(id: "sample_taketori", title: "sample_taketori_title", credit: "sample_ndl_credit", mode: .koten),
        SamplePage(id: "sample_genji", title: "sample_genji_title", credit: "onboarding_sample_credit", mode: .koten),
        SamplePage(id: "sample_kikuchi", title: "sample_kikuchi_title", credit: "sample_kikuchi_credit", mode: .koten),
        SamplePage(id: "sample_shibata", title: "sample_shibata_title", credit: "sample_shibata_credit", mode: .koten),
        SamplePage(id: "sample_modern", title: "sample_modern_title", credit: "sample_ndl_credit", mode: .ndl),
    ]

    var url: URL? { Bundle.main.url(forResource: id, withExtension: "jpg") }

    func loadImage() -> CGImage? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return ImageIntake.decode(data)
    }
}

/// Lists the bundled sample pages; choosing one reads it in that page's mode.
struct SampleSheet: View {
    var onSelect: (SamplePage) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("sample_sheet_lead")
                        .font(.subheadline)
                        .foregroundColor(KotenColor.inkSecondary)
                        .padding(.horizontal, 4)
                    ForEach(Array(SamplePage.all.enumerated()), id: \.element.id) { index, page in
                        Button {
                            dismiss()
                            onSelect(page)
                        } label: {
                            SampleRow(page: page)
                        }
                        .buttonStyle(KotenCardButtonStyle())
                        .accessibilityIdentifier("sample_\(index)")
                    }
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .washiBackground()
            .navigationTitle(Text("sample_sheet_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "cancel", defaultValue: "キャンセル")) { dismiss() }
                }
            }
        }
    }
}

private struct SampleRow: View {
    let page: SamplePage
    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(spacing: 14) {
            KotenColor.mount
                .frame(width: 84, height: 84)
                .overlay {
                    if let thumbnail {
                        Image(uiImage: thumbnail).resizable().scaledToFill()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(KotenColor.rule, lineWidth: 1))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(page.title)
                    .font(.mincho(17, relativeTo: .headline, bold: true))
                    .foregroundColor(KotenColor.ink)
                Text(page.mode.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(KotenColor.shu)
                Text(page.credit)
                    .font(.caption)
                    .foregroundColor(KotenColor.inkSecondary)
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).fill(KotenColor.washiCard))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(KotenColor.rule, lineWidth: 1.5))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .task {
            guard thumbnail == nil, let url = page.url else { return }
            thumbnail = await Task.detached(priority: .utility) {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                          kCGImageSourceCreateThumbnailFromImageAlways: true,
                          kCGImageSourceThumbnailMaxPixelSize: 252,
                          kCGImageSourceCreateThumbnailWithTransform: true,
                      ] as CFDictionary) else { return nil }
                return UIImage(cgImage: cg)
            }.value
        }
    }
}
