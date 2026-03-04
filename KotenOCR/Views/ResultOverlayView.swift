import SwiftUI

struct ResultOverlayView: View {
    let image: CGImage
    @Binding var detections: [Detection]
    @Binding var selectedIndex: Int?
    var historyItemID: UUID?
    @Binding var translatedText: String?
    var onOpenSettings: (() -> Void)?
    @State private var showBoxes = true
    @State private var showCopied = false
    @State private var showShareSheet = false
    @State private var zoom: CGFloat = 1.0
    @State private var steadyZoom: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var steadyOffset: CGSize = .zero
    @State private var editingIndex: Int?
    @State private var editText: String = ""
    @State private var exportFileURL: URL?
    @State private var showExportShare = false
    @State private var isTranslating = false
    @State private var translationError: String?
    @State private var showAPIKeyAlert = false
    @State private var selectedTab: ResultTab = .ocr

    enum ResultTab {
        case ocr
        case translation
    }

    var body: some View {
        VStack(spacing: 0) {
            // Image with boxes + pinch-to-zoom
            Image(decorative: image, scale: 1.0)
                .resizable()
                .scaledToFit()
                // Visual-only box overlay (non-interactive)
                .overlay {
                    GeometryReader { geometry in
                        let scaleX = geometry.size.width / CGFloat(image.width)
                        let scaleY = geometry.size.height / CGFloat(image.height)

                        ForEach(Array(detections.enumerated()), id: \.offset) { index, det in
                            let rect = CGRect(
                                x: CGFloat(det.box[0]) * scaleX,
                                y: CGFloat(det.box[1]) * scaleY,
                                width: CGFloat(det.box[2] - det.box[0]) * scaleX,
                                height: CGFloat(det.box[3] - det.box[1]) * scaleY
                            )
                            let isSelected = selectedIndex == index
                            let color = boxColor(for: index)

                            if showBoxes {
                                Rectangle()
                                    .stroke(color, lineWidth: isSelected ? 3 : 1)
                                    .background(color.opacity(isSelected ? 0.35 : 0.1))
                                    .frame(width: rect.width, height: rect.height)
                                    .overlay(alignment: .topLeading) {
                                        Text("\(index + 1)")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 3)
                                            .padding(.vertical, 1)
                                            .background(color.opacity(0.85))
                                    }
                                    .position(x: rect.midX, y: rect.midY)
                            }
                        }
                    }
                    .allowsHitTesting(false)
                }
                // Tap overlay for box selection (single gesture, no conflict)
                .overlay {
                    GeometryReader { geometry in
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(
                                ExclusiveGesture(
                                    SpatialTapGesture(count: 2),
                                    SpatialTapGesture(count: 1)
                                )
                                .onEnded { value in
                                    switch value {
                                    case .first:
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            if zoom > 1.0 {
                                                zoom = 1.0; steadyZoom = 1.0
                                                offset = .zero; steadyOffset = .zero
                                            } else {
                                                zoom = 3.0; steadyZoom = 3.0
                                            }
                                        }
                                    case .second(let tap):
                                        guard showBoxes else { return }
                                        let scaleX = geometry.size.width / CGFloat(image.width)
                                        let scaleY = geometry.size.height / CGFloat(image.height)
                                        for (index, det) in detections.enumerated() {
                                            let rect = CGRect(
                                                x: CGFloat(det.box[0]) * scaleX,
                                                y: CGFloat(det.box[1]) * scaleY,
                                                width: CGFloat(det.box[2] - det.box[0]) * scaleX,
                                                height: CGFloat(det.box[3] - det.box[1]) * scaleY
                                            )
                                            if rect.contains(tap.location) {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    selectedIndex = selectedIndex == index ? nil : index
                                                }
                                                return
                                            }
                                        }
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            selectedIndex = nil
                                        }
                                    }
                                }
                            )
                    }
                }
                .scaleEffect(zoom)
                .offset(offset)
                .clipped()
                .contentShape(Rectangle())
                .highPriorityGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            zoom = steadyZoom * value
                        }
                        .onEnded { value in
                            steadyZoom = max(1.0, steadyZoom * value)
                            zoom = steadyZoom
                            if steadyZoom == 1.0 {
                                withAnimation { offset = .zero; steadyOffset = .zero }
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            guard zoom > 1.0 else { return }
                            offset = CGSize(
                                width: steadyOffset.width + value.translation.width,
                                height: steadyOffset.height + value.translation.height
                            )
                        }
                        .onEnded { value in
                            steadyOffset = offset
                        }
                )

            // Controls
            HStack(spacing: 12) {
                Toggle(isOn: $showBoxes) {
                    Label(String(localized: "boxes_toggle", defaultValue: "Boxes"), systemImage: "rectangle.dashed")
                        .font(.caption)
                }
                .toggleStyle(.button)
                .tint(showBoxes ? .blue : .gray)
                .accessibilityLabel(Text("boxes_toggle"))

                Spacer()

                Text("\(detections.count) " + String(localized: "history_regions", defaultValue: "regions"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button(action: copyAllText) {
                    Label(showCopied ? String(localized: "copied", defaultValue: "Copied") : String(localized: "copy", defaultValue: "Copy"),
                          systemImage: showCopied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(showCopied ? .green : .blue)
                .accessibilityLabel(Text(showCopied ? "copied" : "copy"))

                // Export menu
                Menu {
                    Button {
                        showShareSheet = true
                    } label: {
                        Label(String(localized: "share_text", defaultValue: "Share Text"), systemImage: "text.bubble")
                    }
                    Button {
                        if let url = ExportManager.exportAsTXT(text: combinedText) {
                            exportFileURL = url
                            showExportShare = true
                        }
                    } label: {
                        Label(String(localized: "export_txt", defaultValue: "Export TXT"), systemImage: "doc.text")
                    }
                    Button {
                        if let url = ExportManager.exportAsPDF(text: combinedText, image: image) {
                            exportFileURL = url
                            showExportShare = true
                        }
                    } label: {
                        Label(String(localized: "export_pdf", defaultValue: "Export PDF"), systemImage: "doc.richtext")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
                .accessibilityLabel(Text("share"))
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(text: combinedText)
            }
            .sheet(isPresented: $showExportShare) {
                if let url = exportFileURL {
                    ShareSheet(text: url.path, url: url)
                }
            }

            // Tab picker
            Picker("", selection: $selectedTab) {
                Text(String(localized: "tab_ocr", defaultValue: "OCR結果"))
                    .tag(ResultTab.ocr)
                Text(String(localized: "tab_translation", defaultValue: "現代語訳"))
                    .tag(ResultTab.translation)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 6)

            Divider().background(Color.secondary.opacity(0.3))

            // Tab content
            switch selectedTab {
            case .ocr:
                ocrTextList
            case .translation:
                translationPanel
            }
        }
        .sheet(item: $editingIndex) { index in
            editSheet(for: index)
        }
        .alert(String(localized: "translation_no_key_title", defaultValue: "APIキーが必要です"),
               isPresented: $showAPIKeyAlert) {
            Button(String(localized: "translation_open_settings", defaultValue: "設定を開く")) {
                showAPIKeyAlert = false
                onOpenSettings?()
            }
            Button(String(localized: "cancel", defaultValue: "キャンセル"), role: .cancel) {}
        } message: {
            Text(String(localized: "translation_no_key_message", defaultValue: "設定画面でOpenAI互換APIキーを登録してください。"))
        }
    }

    // MARK: - Edit Sheet

    private func editSheet(for index: Int) -> some View {
        NavigationView {
            VStack {
                TextEditor(text: $editText)
                    .font(.system(.body, design: .serif))
                    .padding()
            }
            .navigationTitle(String(localized: "edit_detection_title", defaultValue: "Edit Text"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "edit_cancel", defaultValue: "Cancel")) {
                        editingIndex = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "edit_save", defaultValue: "Save")) {
                        if let idx = editingIndex, idx < detections.count {
                            detections[idx].text = editText
                        }
                        editingIndex = nil
                    }
                }
            }
        }
    }

    // MARK: - OCR Text List

    private var ocrTextList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(detections.enumerated()), id: \.offset) { index, det in
                        let isSelected = selectedIndex == index
                        let color = boxColor(for: index)

                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1)")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(isSelected ? color : .secondary)
                                .frame(width: 24, alignment: .trailing)

                            Text(det.text.isEmpty ? "---" : det.text)
                                .font(.system(.body, design: .serif))
                                .foregroundColor(det.text.isEmpty ? .secondary : .primary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isSelected ? color.opacity(0.2) : Color.clear)
                        )
                        .id(index)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedIndex = selectedIndex == index ? nil : index
                            }
                        }
                        .onLongPressGesture {
                            editingIndex = index
                            editText = det.text
                        }
                        .accessibilityLabel(Text("\(index + 1): \(det.text)"))
                        .accessibilityHint(Text("edit_text"))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .onChange(of: selectedIndex) { newValue in
                if let idx = newValue {
                    withAnimation {
                        proxy.scrollTo(idx, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Translation Panel

    private var translationPanel: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let translated = translatedText, !translated.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button(action: startTranslation) {
                                Label(String(localized: "retranslate_button", defaultValue: "再翻訳"),
                                      systemImage: "arrow.clockwise")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange)
                            .disabled(isTranslating)

                            Spacer()

                            Button {
                                #if canImport(UIKit)
                                UIPasteboard.general.string = translated
                                #endif
                            } label: {
                                Label(String(localized: "copy", defaultValue: "Copy"), systemImage: "doc.on.doc")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .tint(.blue)
                        }
                        Text(translated)
                            .font(.system(.body, design: .serif))
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }

                if isTranslating {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(String(localized: "translating", defaultValue: "翻訳中..."))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }

                if let error = translationError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 12)
                }

                if translatedText == nil && !isTranslating {
                    VStack(spacing: 16) {
                        Image(systemName: "text.book.closed")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                        Text(String(localized: "translation_empty", defaultValue: "現代語訳がまだありません"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Button(action: startTranslation) {
                            HStack {
                                Image(systemName: "sparkles")
                                Text(String(localized: "translate_button", defaultValue: "現代語訳"))
                            }
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(Color.blue)
                            .cornerRadius(8)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            }
        }
    }

    // MARK: - Translation Logic

    private func startTranslation() {
        Task {
            let provider = await TranslationService.shared.loadProvider()
            let hasKey = await TranslationService.shared.hasAPIKey
            await MainActor.run {
                if !provider.requiresAPIKey || hasKey {
                    performTranslation()
                } else {
                    showAPIKeyAlert = true
                }
            }
        }
    }

    private func performTranslation() {
        isTranslating = true
        translationError = nil
        Task {
            do {
                let result = try await TranslationService.shared.translate(text: combinedText)
                await MainActor.run {
                    translatedText = result
                    isTranslating = false
                    if let id = historyItemID {
                        HistoryManager.shared.updateTranslation(for: id, translatedText: result)
                    }
                }
            } catch {
                await MainActor.run {
                    translationError = error.localizedDescription
                    isTranslating = false
                }
            }
        }
    }

    private var combinedText: String {
        detections.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private func copyAllText() {
        #if canImport(UIKit)
        UIPasteboard.general.string = combinedText
        showCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showCopied = false
        }
        #endif
    }

    private func boxColor(for index: Int) -> Color {
        let colors: [Color] = [.red, .green, .blue, .orange, .purple, .cyan, .yellow, .pink]
        return colors[index % colors.count]
    }
}

// Make Int conform to Identifiable for .sheet(item:)
extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let text: String
    var url: URL? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        var items: [Any] = []
        if let url = url {
            items.append(url)
        } else {
            items.append(text)
        }
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
