import SwiftUI

struct HistoryListView: View {
    @ObservedObject var historyManager = HistoryManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteAllConfirm = false
    @State private var itemToDelete: HistoryItem?
    var onSelect: (HistoryItem) -> Void
    /// Shown as the main button on the empty state.
    var onStartCamera: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            Group {
                if historyManager.items.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(historyManager.items) { item in
                            HStack(spacing: 8) {
                                Button {
                                    onSelect(item)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        HistoryThumbnailView(item: item)

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.text.prefix(50).replacingOccurrences(of: "\n", with: " "))
                                                .font(.mincho(16, relativeTo: .subheadline))
                                                .foregroundColor(KotenColor.ink)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                            Text(item.date, style: .date)
                                                .font(.caption)
                                                .foregroundColor(KotenColor.inkSecondary)
                                            HStack(spacing: 6) {
                                                Text(String(format: String(localized: "lines_count_format", defaultValue: "%d 行"), item.detections.count))
                                                    .font(.caption2)
                                                    .foregroundColor(KotenColor.inkSecondary)
                                                if item.translatedText != nil {
                                                    Text(String(localized: "history_translated_badge", defaultValue: "翻訳済"))
                                                        .font(.caption2.weight(.semibold))
                                                        .foregroundColor(KotenColor.shu)
                                                        .padding(.horizontal, 5)
                                                        .padding(.vertical, 1)
                                                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(KotenColor.shu, lineWidth: 1))
                                                }
                                            }
                                        }

                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text(Self.accessibilityLabel(for: item)))

                                Button {
                                    itemToDelete = item
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.subheadline)
                                        .foregroundColor(KotenColor.shu)
                                        .frame(width: 40, height: 40)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(Text("history_delete_item"))
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(KotenColor.washiCard)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                historyManager.delete(item: historyManager.items[index])
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .washiBackground()
            .tint(KotenColor.shu)
            .accessibilityIdentifier("history_list")
            .navigationTitle(String(localized: "history_title", defaultValue: "履歴"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !historyManager.items.isEmpty {
                        Button(role: .destructive) {
                            showDeleteAllConfirm = true
                        } label: {
                            Text(String(localized: "history_delete_all", defaultValue: "Delete All"))
                        }
                        .accessibilityLabel(Text("history_delete_all"))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(KotenColor.ink)
                    }
                    .accessibilityLabel(Text("close"))
                }
            }
        }
        .confirmationDialog(
            String(localized: "history_delete_item_title", defaultValue: "この履歴を削除しますか？"),
            isPresented: Binding(get: { itemToDelete != nil }, set: { if !$0 { itemToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(String(localized: "history_delete_item", defaultValue: "削除"), role: .destructive) {
                if let item = itemToDelete { historyManager.delete(item: item) }
                itemToDelete = nil
            }
            Button(String(localized: "cancel", defaultValue: "Cancel"), role: .cancel) { itemToDelete = nil }
        }
        .alert(String(localized: "history_delete_all_title", defaultValue: "Delete All History"),
               isPresented: $showDeleteAllConfirm) {
            Button(String(localized: "history_delete_all", defaultValue: "Delete All"), role: .destructive) {
                historyManager.deleteAll()
            }
            Button(String(localized: "cancel", defaultValue: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "history_delete_all_message", defaultValue: "Are you sure you want to delete all scan history? This cannot be undone."))
        }
    }

    /// Storyboard guidance 3: a brush circle (円相) with a small 朱印, and one main action.
    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 0) {
                EmptyHistoryIllustration()
                    .frame(width: 170, height: 170)
                    .padding(.top, 80)
                Text("history_empty_title")
                    .font(.mincho(24, relativeTo: .title2, bold: true))
                    .foregroundColor(KotenColor.ink)
                    .multilineTextAlignment(.center)
                    .padding(.top, 22)
                    .accessibilityIdentifier("history_empty")
                Text("history_empty_body")
                    .font(.body)
                    .foregroundColor(KotenColor.inkSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            if let onStartCamera {
                Button {
                    dismiss()
                    onStartCamera()
                } label: {
                    Text("home_take_photo")
                        .font(.title3.weight(.heavy))
                        .frame(maxWidth: .infinity, minHeight: 58)
                }
                .buttonStyle(.kotenProminent)
                .accessibilityIdentifier("history_empty_camera_button")
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
    }

    /// "<date>, <first line of text>" so VoiceOver users can tell rows apart.
    static func accessibilityLabel(for item: HistoryItem, locale: Locale = .current) -> String {
        let date = item.date.formatted(.dateTime.year().month().day().hour().minute().locale(locale))
        let firstLine = item.text.split(whereSeparator: \.isNewline).first.map { String($0.prefix(50)) } ?? ""
        let base = String(localized: "history_item_label", defaultValue: "スキャン結果")
        return [base, date, firstLine].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// Brush circle drawn as an open, slightly uneven stroke, with a small tilted 朱印.
private struct EmptyHistoryIllustration: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height) / 200
            ZStack(alignment: .topLeading) {
                EnsoShape()
                    .stroke(KotenColor.ink.opacity(0.85),
                            style: StrokeStyle(lineWidth: 13 * s, lineCap: .round, lineJoin: .round))
                KotenStamp(size: 44 * s)
                    .rotationEffect(.degrees(1))
                    .offset(x: 118 * s, y: 130 * s)
            }
            .frame(width: 200 * s, height: 200 * s)
        }
        .accessibilityHidden(true)
    }
}

/// The 円相 path from the storyboard (viewBox 200×200), not quite closed.
private struct EnsoShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 200
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        var p = Path()
        p.move(to: pt(100, 22))
        p.addCurve(to: pt(178, 104), control1: pt(150, 20), control2: pt(182, 58))
        p.addCurve(to: pt(92, 178), control1: pt(174, 152), control2: pt(136, 182))
        p.addCurve(to: pt(24, 94), control1: pt(46, 174), control2: pt(20, 138))
        p.addCurve(to: pt(96, 24), control1: pt(27, 58), control2: pt(52, 30))
        return p
    }
}

/// Loads the downsampled thumbnail off the main thread.
private struct HistoryThumbnailView: View {
    let item: HistoryItem
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .cornerRadius(8)
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(KotenColor.mount)
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: "doc.text")
                            .foregroundColor(KotenColor.inkSecondary)
                    }
            }
        }
        .accessibilityHidden(true)
        .task(id: item.id) {
            image = await HistoryManager.shared.thumbnail(for: item)
        }
    }
}
