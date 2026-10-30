import SwiftUI
import PhotosUI

/// Start screen shown on every launch (after onboarding), before the camera.
/// Content side (cards, headings, thumbnails) is washi and Mincho; the settings button is glass.
struct HomeView: View {
    @Binding var selectedPhotoItem: PhotosPickerItem?
    let onCamera: () -> Void
    let onHistory: () -> Void
    let onSettings: () -> Void
    var onOpenHistoryItem: (HistoryItem) -> Void = { _ in }

    @ObservedObject private var historyManager = HistoryManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Two-step entrance after the launch screen fades: the header (1), then the rest (2).
    @State private var appeared = 0

    private var recentItems: [HistoryItem] { Array(historyManager.items.prefix(3)) }

    var body: some View {
        // The page fills at least the screen: the header at the top, the actions at the bottom
        // within thumb reach, and recent scans (or a short how-to) centred in between.
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        // The wordmark is a logo: it stops growing at xxxLarge so it never pushes the layout wide.
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .opacity(appeared >= 1 ? 1 : 0)

                    VStack(alignment: .leading, spacing: 0) {
                        Spacer(minLength: 28)
                        if recentItems.isEmpty {
                            steps
                        } else {
                            recentSection
                        }
                        Spacer(minLength: 28)

                        if !recentItems.isEmpty {
                            howTo
                                .padding(.bottom, 16)
                        }
                        mainCard
                        secondaryRow
                            .padding(.top, 12)
                    }
                    .opacity(appeared >= 2 ? 1 : 0)
                    .offset(y: appeared >= 2 || reduceMotion ? 0 : 10)
                }
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 16)
                .frame(minHeight: geo.size.height)
            }
        }
        .washiBackground()
        .onAppear(perform: playEntrance)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            brand
            Spacer(minLength: 8)
            Button(action: onSettings) {
                KotenIconLabel(systemName: "gearshape")
            }
            .buttonStyle(.kotenGlassCircle)
            .accessibilityIdentifier("home_settings_button")
            .accessibilityLabel(Text("settings_button"))
        }
    }

    @ViewBuilder private var brand: some View {
        let seal = KotenSeal(size: 40)
        let name = Text("KotenOCR")
            .font(.mincho(28, relativeTo: .title, bold: true))
            .foregroundColor(KotenColor.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
        HStack(spacing: 12) {
            seal
            name
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Cards

    private var mainCard: some View {
        Button(action: {
            KotenHaptics.impact(.medium)
            onCamera()
        }) {
            HStack(spacing: 20) {
                Image(systemName: "camera")
                    .font(.system(size: 40, weight: .light))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("home_take_photo")
                        .font(.mincho(28, relativeTo: .title, bold: true))
                    Text("home_take_photo_sub")
                        .font(.subheadline)
                        .opacity(0.75)
                }
                Spacer(minLength: 0)
            }
            .foregroundColor(KotenColor.washi)
            .padding(.horizontal, 26)
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity, minHeight: 128)
            .background(RoundedRectangle(cornerRadius: 18).fill(KotenColor.ink))
            .shadow(color: KotenColor.ink.opacity(0.25), radius: 12, y: 10)
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(KotenCardButtonStyle())
        .accessibilityIdentifier("home_camera_button")
        .padding(.horizontal, 20)
    }

    private var secondaryRow: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                secondaryLabel(icon: "photo", title: "home_choose_photo")
            }
            .buttonStyle(KotenCardButtonStyle())
            .accessibilityIdentifier("home_photo_button")

            Button(action: onHistory) {
                secondaryLabel(icon: "clock", title: "history_button")
            }
            .buttonStyle(KotenCardButtonStyle())
            .accessibilityIdentifier("home_history_button")
        }
        .padding(.horizontal, 20)
    }

    private func secondaryLabel(icon: String, title: LocalizedStringKey) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .light))
                .accessibilityHidden(true)
            Text(title)
                .font(.mincho(17, relativeTo: .headline, bold: true))
                .multilineTextAlignment(.center)
        }
        .foregroundColor(KotenColor.ink)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 92)
        .background(RoundedRectangle(cornerRadius: 16).fill(KotenColor.washiCard))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(KotenColor.rule, lineWidth: 1.5))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }

    private var howTo: some View {
        Text("home_how_to")
            .font(.subheadline)
            .foregroundColor(KotenColor.inkSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .overlay(alignment: .top) { KotenColor.rule.frame(height: 1) }
            .overlay(alignment: .bottom) { KotenColor.rule.frame(height: 1) }
            .padding(.horizontal, 20)
    }

    /// Shown while there are no scans yet: the tagline and the three steps, one per line.
    private var steps: some View {
        let parts = String(localized: "home_how_to")
            .components(separatedBy: "→")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return VStack(spacing: 18) {
            Text("brand_tagline")
                .font(.mincho(20, relativeTo: .title3, bold: true))
                .tracking(1)
                .foregroundColor(KotenColor.ink)
                .multilineTextAlignment(.center)
            KotenColor.shu.opacity(0.6)
                .frame(width: 32, height: 1.5)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text("\(index + 1)")
                            .font(.mincho(17, relativeTo: .body, bold: true))
                            .foregroundColor(KotenColor.shu)
                            .accessibilityHidden(true)
                        Text(part)
                            .font(.mincho(17, relativeTo: .body))
                            .foregroundColor(KotenColor.inkSecondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Recent scans

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("home_recent")
                .font(.mincho(16, relativeTo: .headline, bold: true))
                .foregroundColor(KotenColor.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 24)
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(recentItems.enumerated()), id: \.element.id) { index, item in
                    Button { onOpenHistoryItem(item) } label: {
                        RecentThumbnail(item: item, height: recentThumbnailHeight)
                    }
                    .buttonStyle(KotenCardButtonStyle())
                    .accessibilityLabel(Text(HistoryListView.accessibilityLabel(for: item)))
                    .accessibilityIdentifier("home_recent_\(index)")
                }
            }
            // With one or two scans the tiles grow and sit in the middle, so the page does not look empty.
            .frame(maxWidth: recentItems.count == 1 ? 240 : .infinity)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, recentItems.count == 2 ? 36 : 20)
        }
    }

    private var recentThumbnailHeight: CGFloat {
        switch recentItems.count {
        case 1: return 280
        case 2: return 200
        default: return 150
        }
    }

    // MARK: - Motion

    private func playEntrance() {
        guard appeared == 0 else { return }
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.25)) { appeared = 2 }
            return
        }
        // While the launch screen cross-fades out (0.4 s), the header fades in; then the cards
        // and recent scans rise 10pt together. Everything is still by about 0.75 s.
        withAnimation(.easeInOut(duration: 0.45)) { appeared = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeOut(duration: 0.55)) { appeared = 2 }
        }
    }
}

/// Thumbnail with date and line count, from the 200px history thumbnail.
private struct RecentThumbnail: View {
    let item: HistoryItem
    var height: CGFloat = 112
    @State private var image: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // The thumbnail fills the tile without asking for more width than the tile has.
            KotenColor.mount
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .overlay {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(KotenColor.rule, lineWidth: 1))

            Text(caption)
                .font(.caption)
                .foregroundColor(KotenColor.inkSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity)
        .task(id: "\(item.id)-\(height)") {
            image = height > 112
                ? await HistoryManager.shared.preview(for: item, maxPixel: height * 3)
                : await HistoryManager.shared.thumbnail(for: item)
        }
    }

    private var caption: String {
        let date = item.date.formatted(.dateTime.month(.defaultDigits).day())
        let lines = String(format: String(localized: "lines_count_format", defaultValue: "%d 行"), item.detections.count)
        return "\(date)  \(lines)"
    }
}
