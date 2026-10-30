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
    /// Shared with the launch screen so the seal and name can move into the header.
    var brandNamespace: Namespace.ID?

    @ObservedObject private var historyManager = HistoryManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Staggered entrance: cards rise one after another, the glass button comes last.
    @State private var appeared = 0

    private var recentItems: [HistoryItem] { Array(historyManager.items.prefix(3)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    // The wordmark is a logo: it stops growing at xxxLarge so it never pushes the layout wide.
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                mainCard
                    .rise(appeared >= 1, reduceMotion: reduceMotion)
                    .padding(.top, 22)

                secondaryRow
                    .rise(appeared >= 2, reduceMotion: reduceMotion)
                    .padding(.top, 12)

                howTo
                    .rise(appeared >= 3, reduceMotion: reduceMotion)
                    .padding(.top, 18)

                if !recentItems.isEmpty {
                    recentSection
                        .rise(appeared >= 4, reduceMotion: reduceMotion)
                        .padding(.top, 20)
                }
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 32)
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
            .scaleEffect(appeared >= 5 || reduceMotion ? 1 : 0.8)
            .opacity(appeared >= 5 ? 1 : 0)
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
            if let ns = brandNamespace {
                seal.matchedGeometryEffect(id: "brandSeal", in: ns)
                name.matchedGeometryEffect(id: "brandName", in: ns)
            } else {
                seal
                name
            }
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

    // MARK: - Recent scans

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("home_recent")
                .font(.mincho(16, relativeTo: .headline, bold: true))
                .foregroundColor(KotenColor.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 24)
            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(recentItems.enumerated()), id: \.element.id) { index, item in
                    Button { onOpenHistoryItem(item) } label: {
                        RecentThumbnail(item: item)
                    }
                    .buttonStyle(KotenCardButtonStyle())
                    .accessibilityLabel(Text(HistoryListView.accessibilityLabel(for: item)))
                    .accessibilityIdentifier("home_recent_\(index)")
                }
                // Keep three equal columns even when there are fewer items.
                ForEach(recentItems.count..<3, id: \.self) { _ in
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Motion

    private func playEntrance() {
        guard appeared == 0 else { return }
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.2)) { appeared = 5 }
            return
        }
        // Cards rise 24pt, 60ms apart, ease-out; the glass settings button comes last.
        for step in 1...5 {
            let delay = step == 5 ? 0.3 : 0.06 * Double(step - 1)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeOut(duration: step == 5 ? 0.2 : 0.3)) { appeared = max(appeared, step) }
            }
        }
    }
}

private extension View {
    func rise(_ visible: Bool, reduceMotion: Bool) -> some View {
        self
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 24)
    }
}

/// Thumbnail with date and line count, from the 200px history thumbnail.
private struct RecentThumbnail: View {
    let item: HistoryItem
    @State private var image: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // The thumbnail fills the tile without asking for more width than the tile has.
            KotenColor.mount
                .frame(maxWidth: .infinity)
                .frame(height: 96)
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
        .task(id: item.id) {
            image = await HistoryManager.shared.thumbnail(for: item)
        }
    }

    private var caption: String {
        let date = item.date.formatted(.dateTime.month(.defaultDigits).day())
        let lines = String(format: String(localized: "lines_count_format", defaultValue: "%d 行"), item.detections.count)
        return "\(date)  \(lines)"
    }
}
