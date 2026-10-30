import SwiftUI

struct HistoryListView: View {
    @ObservedObject var historyManager = HistoryManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteAllConfirm = false
    @State private var itemToDelete: HistoryItem?
    var onSelect: (HistoryItem) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if historyManager.items.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text(String(localized: "history_empty", defaultValue: "No scan history yet"))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                                                .font(.subheadline)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                            Text(item.date, style: .date)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            HStack(spacing: 6) {
                                                Text("\(item.detections.count) " + String(localized: "history_regions", defaultValue: "regions"))
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                if item.translatedText != nil {
                                                    Text(String(localized: "history_translated_badge", defaultValue: "翻訳済"))
                                                        .font(.caption2)
                                                        .foregroundColor(.blue)
                                                        .padding(.horizontal, 4)
                                                        .padding(.vertical, 1)
                                                        .background(Color.blue.opacity(0.1))
                                                        .cornerRadius(3)
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
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .frame(width: 36, height: 36)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(Text("history_delete_item"))
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                historyManager.delete(item: historyManager.items[index])
                            }
                        }
                    }
                }
            }
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
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
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

    /// "<date>, <first line of text>" so VoiceOver users can tell rows apart.
    static func accessibilityLabel(for item: HistoryItem, locale: Locale = .current) -> String {
        let date = item.date.formatted(.dateTime.year().month().day().hour().minute().locale(locale))
        let firstLine = item.text.split(whereSeparator: \.isNewline).first.map { String($0.prefix(50)) } ?? ""
        let base = String(localized: "history_item_label", defaultValue: "スキャン結果")
        return [base, date, firstLine].filter { !$0.isEmpty }.joined(separator: ", ")
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
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: "doc.text")
                            .foregroundColor(.secondary)
                    }
            }
        }
        .accessibilityHidden(true)
        .task(id: item.id) {
            image = await HistoryManager.shared.thumbnail(for: item)
        }
    }
}
