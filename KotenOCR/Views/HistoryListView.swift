import SwiftUI

struct HistoryListView: View {
    @ObservedObject var historyManager = HistoryManager.shared
    @Environment(\.dismiss) private var dismiss
    var onSelect: (HistoryItem) -> Void

    var body: some View {
        NavigationView {
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
                            Button {
                                onSelect(item)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    if let uiImage = loadThumbnail(for: item) {
                                        Image(uiImage: uiImage)
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

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.text.prefix(50).replacingOccurrences(of: "\n", with: " "))
                                            .font(.subheadline)
                                            .lineLimit(2)
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

                                    Button(role: .destructive) {
                                        historyManager.delete(item: item)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.caption)
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel(Text("history_delete_item"))
                                }
                                .padding(.vertical, 4)
                            }
                            .accessibilityLabel(Text("history_item_label"))
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                historyManager.delete(item: historyManager.items[index])
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "history_title", defaultValue: "履歴"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !historyManager.items.isEmpty {
                        Button(role: .destructive) {
                            historyManager.deleteAll()
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
    }

    private func loadThumbnail(for item: HistoryItem) -> UIImage? {
        guard let data = try? Data(contentsOf: item.imagePath),
              let image = UIImage(data: data) else { return nil }
        return image
    }
}
