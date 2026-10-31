import SwiftUI

struct ResultOverlayView: View {
    let image: CGImage
    @Binding var detections: [Detection]
    @Binding var selectedIndex: Int?
    var historyItemID: UUID?
    @Binding var translatedText: String?
    var onOpenSettings: (() -> Void)?
    /// Set by ContentView when the result comes straight from a scan: the 朱 stamp is pressed once.
    var playCompletionStamp: Binding<Bool> = .constant(false)
    /// While editing boxes, the current number of lines (nil when not editing). Lets the header count follow edits.
    var editingLineCount: Binding<Int?> = .constant(nil)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var ocrEngine: OCREngine
    @StateObject private var edit = BoxEditModel()
    @State private var stampPhase = 0
    @State private var showBoxes = true
    @State private var showCopied = false
    @State private var showShareSheet = false
    @State private var zoom: CGFloat = 1.0
    @State private var steadyZoom: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var steadyOffset: CGSize = .zero
    @State private var imageContainerSize: CGSize = .zero
    @State private var lastTouchLocation: CGPoint = .zero
    @State private var isPinching: Bool = false
    @State private var editingIndex: Int?
    @State private var editText: String = ""
    @State private var exportFileURL: URL?
    @State private var showExportShare = false
    @State private var isTranslating = false
    @State private var translationError: String?
    @State private var showAPIKeyAlert = false
    @State private var selectedTab: ResultTab = .ocr
    /// Display filter only: lines scoring below this are hidden. Nothing stored changes.
    @State private var confidenceThreshold: Float = ConfidenceFilter.defaultThreshold
    @State private var thresholdInitialised = false

    enum ResultTab {
        case ocr
        case translation
    }

    var body: some View {
        VStack(spacing: 0) {
            // Image with boxes + pinch-to-zoom, on a paper mount
            ZStack {
                KotenColor.mount

                Image(decorative: image, scale: 1.0)
                    .resizable()
                    .scaledToFit()
                    // Visual-only box overlay (non-interactive)
                    .overlay {
                        GeometryReader { geometry in
                            let scaleX = image.width > 0 ? geometry.size.width / CGFloat(image.width) : 0
                            let scaleY = image.height > 0 ? geometry.size.height / CGFloat(image.height) : 0

                            let lines = visibleLines
                            let rects: [CGRect] = lines.map { line in
                                let det = line.detection
                                return CGRect(
                                    x: CGFloat(det.box[0]) * scaleX,
                                    y: CGFloat(det.box[1]) * scaleY,
                                    width: CGFloat(det.box[2] - det.box[0]) * scaleX,
                                    height: CGFloat(det.box[3] - det.box[1]) * scaleY
                                )
                            }

                            if showBoxes && !edit.isActive {
                                // Divided by the zoom so lines keep their on-screen thickness when zoomed.
                                let lineWidth = LineTagLayout.boxLineWidth(for: rects) / zoom
                                ForEach(Array(rects.enumerated()), id: \.offset) { index, rect in
                                    let isSelected = selectedIndex == lines[index].index
                                    let color = boxColor(for: index)
                                    Rectangle()
                                        .stroke(color, lineWidth: isSelected ? lineWidth * 2 : lineWidth)
                                        .background(color.opacity(isSelected ? 0.3 : 0.08))
                                        .frame(width: rect.width, height: rect.height)
                                        .position(x: rect.midX, y: rect.midY)
                                }
                                // Numbers sit at the start of each line, outside the box, so they never hide the first characters.
                                let tagBounds = CGRect(origin: .zero, size: geometry.size)
                                // Tags of crowded lines may touch: a thin white rim keeps them apart and they let
                                // the page show through a little; the selected line's tag is solid and on top.
                                ForEach(Array(LineTagLayout.frames(for: rects, in: tagBounds).enumerated()), id: \.offset) { index, tag in
                                    let isSelected = selectedIndex == lines[index].index
                                    Text("\(index + 1)")
                                        .font(.system(size: tag.height * 0.75, weight: .bold))
                                        .monospacedDigit()
                                        .foregroundColor(.white)
                                        .frame(width: tag.width, height: tag.height)
                                        .background(Capsule().fill(KotenColor.shuFill))
                                        .overlay(Capsule().stroke(Color.white, lineWidth: max(0.5, tag.height / 16)))
                                        .opacity(isSelected ? 1 : 0.85)
                                        .fixedSize()
                                        .position(x: tag.midX, y: tag.midY)
                                        .zIndex(isSelected ? 1 : 0)
                                }
                            }
                        }
                        .allowsHitTesting(false)
                    }
                    // Box editing: boxes and corner handles
                    .overlay {
                        if edit.isActive {
                            BoxEditCanvas(model: edit,
                                          imageSize: CGSize(width: image.width, height: image.height),
                                          zoom: zoom)
                        }
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
                                        case .first(let doubleTap):
                                            withAnimation(.easeInOut(duration: 0.3)) {
                                                if zoom > 1.0 {
                                                    zoom = 1.0; steadyZoom = 1.0
                                                    offset = .zero; steadyOffset = .zero
                                                } else {
                                                    let newZoom: CGFloat = 3.0
                                                    let px = doubleTap.location.x - imageContainerSize.width / 2
                                                    let py = doubleTap.location.y - imageContainerSize.height / 2
                                                    offset = CGSize(
                                                        width: px - px * newZoom,
                                                        height: py - py * newZoom
                                                    )
                                                    steadyOffset = offset
                                                    zoom = newZoom; steadyZoom = newZoom
                                                }
                                            }
                                        case .second(let tap):
                                            guard showBoxes else { return }
                                            let scaleX = geometry.size.width / CGFloat(image.width)
                                            let scaleY = geometry.size.height / CGFloat(image.height)
                                            for (index, det) in visibleLines.map({ ($0.index, $0.detection) }) {
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
                        .allowsHitTesting(!edit.isActive)
                    }
                    .scaleEffect(zoom)
                    .offset(offset)

                // Touches for box editing live outside the zoomed image so they stay in screen space.
                if edit.isActive {
                    BoxEditGestureLayer(model: edit,
                                        imageSize: CGSize(width: image.width, height: image.height),
                                        zoom: zoom, offset: $offset, steadyOffset: $steadyOffset,
                                        isPinching: isPinching,
                                        onHaptic: { KotenHaptics.notify(.warning) })
                }
            }
            .clipped()
            .overlay(alignment: .topTrailing) { completionStamp }
            .padding(6)
            .background(KotenColor.mount)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(KotenColor.rule, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(color: Color(red: 0.31, green: 0.24, blue: 0.12).opacity(0.15), radius: 8, y: 6)
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            imageContainerSize = geo.size
                            lastTouchLocation = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                        }
                        .onChange(of: geo.size) { imageContainerSize = $0 }
                }
            )
            .contentShape(Rectangle())
            // Track touch location for pinch anchor
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isPinching {
                            lastTouchLocation = value.startLocation
                        }
                        // Pan when zoomed (single finger, not during pinch)
                        if !isPinching && zoom > 1.0 && !edit.isActive {
                            offset = CGSize(
                                width: steadyOffset.width + value.translation.width,
                                height: steadyOffset.height + value.translation.height
                            )
                        }
                    }
                    .onEnded { _ in
                        if !isPinching && !edit.isActive {
                            steadyOffset = offset
                        }
                    }
            )
            // Pinch zoom anchored at touch location
            .highPriorityGesture(
                MagnificationGesture()
                    .onChanged { value in
                        isPinching = true
                        let newZoom = max(1.0, steadyZoom * value)
                        let ratio = newZoom / max(steadyZoom, 0.01)
                        // Pinch center relative to container center
                        let px = lastTouchLocation.x - imageContainerSize.width / 2
                        let py = lastTouchLocation.y - imageContainerSize.height / 2
                        offset = CGSize(
                            width: px - (px - steadyOffset.width) * ratio,
                            height: py - (py - steadyOffset.height) * ratio
                        )
                        zoom = newZoom
                    }
                    .onEnded { _ in
                        isPinching = false
                        steadyZoom = max(1.0, zoom)
                        zoom = steadyZoom
                        steadyOffset = offset
                        if steadyZoom <= 1.0 {
                            withAnimation { offset = .zero; steadyOffset = .zero }
                        }
                    }
            )

            // Controls (glass)
            if edit.isActive {
                BoxEditControls(model: edit, onCancel: cancelEditing, onDone: finishEditing, onReread: startReread)
            } else {
            HStack(spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showBoxes.toggle() }
                } label: {
                    Label(String(localized: "boxes_toggle", defaultValue: "Boxes"),
                          systemImage: showBoxes ? "rectangle.dashed" : "rectangle.slash")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 40)
                        .opacity(showBoxes ? 1 : 0.6)
                }
                .buttonStyle(.kotenGlass)
                .accessibilityLabel(Text("boxes_toggle"))
                .accessibilityAddTraits(showBoxes ? [.isSelected] : [])

                Button(action: beginEditing) {
                    Label(String(localized: "box_edit_enter", defaultValue: "枠を直す"),
                          systemImage: "rectangle.and.pencil.and.ellipsis")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 40)
                }
                .buttonStyle(.kotenGlass)
                .accessibilityLabel(Text("box_edit_enter"))
                .accessibilityIdentifier("box_edit_enter")

                Spacer()

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
                    KotenIconLabel(systemName: "square.and.arrow.up")
                        .foregroundColor(KotenColor.ink)
                        .kotenGlass(.regular, in: Circle(), interactive: true)
                }
                .accessibilityLabel(Text("share"))
                .accessibilityIdentifier("share_menu")
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            }
            Color.clear.frame(height: 0)
                .sheet(isPresented: $showShareSheet) {
                ShareSheet(text: combinedText)
            }
            .sheet(isPresented: $showExportShare) {
                if let url = exportFileURL {
                    ShareSheet(text: url.path, url: url)
                }
            }

            if !edit.isActive {
                confidenceControl
            }

            // Tab picker
            if !edit.isActive {
            Picker("", selection: $selectedTab) {
                Text(String(localized: "tab_ocr", defaultValue: "OCR結果"))
                    .tag(ResultTab.ocr)
                Text(String(localized: "tab_translation", defaultValue: "現代語訳"))
                    .tag(ResultTab.translation)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .animation(KotenMotion.spring(0.28, reduceMotion: reduceMotion), value: selectedTab)
            }

            // Tab content
            ZStack {
                switch selectedTab {
                case .ocr:
                    ocrTextList.transition(.opacity)
                case .translation:
                    translationPanel.transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: selectedTab)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .bottomTrailing) { if !edit.isActive { copyButton } }
        }
        .overlay(alignment: .top) {
            if showCopied {
                copiedToast
                    .padding(.top, 8)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear {
            playStampIfNeeded()
            if !thresholdInitialised {
                thresholdInitialised = true
                confidenceThreshold = ConfidenceFilter.defaultThreshold
                syncLineCount()
            }
        }
        .onChange(of: confidenceThreshold) { _ in syncLineCount() }
        .onChange(of: detections.count) { _ in syncLineCount() }
        .onChange(of: edit.editor?.items.count) { newValue in
            editingLineCount.wrappedValue = newValue
        }
        .onChange(of: edit.editor?.selected) { newValue in
            if edit.isActive, selectedIndex != newValue { selectedIndex = newValue }
        }
        .onChange(of: selectedIndex) { newValue in
            if edit.isActive, edit.editor?.selected != newValue { edit.editor?.selected = newValue }
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

    // MARK: - Confidence filter

    private var hiddenCount: Int { detections.count - visibleLines.count }

    private var confidenceControl: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Text(String(localized: "confidence_label", defaultValue: "確信度"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(KotenColor.ink)
                Slider(value: $confidenceThreshold, in: ConfidenceFilter.range, step: 0.05)
                    .tint(KotenColor.shu)
                    .accessibilityLabel(Text("confidence_label"))
                    .accessibilityIdentifier("confidence_slider")
                Text(ConfidenceFilter.percentText(confidenceThreshold))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundColor(KotenColor.ink)
                    .frame(minWidth: 44, alignment: .trailing)
                    .accessibilityIdentifier("confidence_value")
            }
            Text(hiddenCount > 0
                 ? String(format: String(localized: "confidence_hint_hidden", defaultValue: "上げると自信のない枠から隠れます（目安 50%%）。いま %d 行を隠しています"), hiddenCount)
                 : String(localized: "confidence_hint", defaultValue: "上げると自信のない枠から隠れます（目安 50%）。表示だけの変更です"))
                .font(.caption)
                .foregroundColor(KotenColor.inkSecondary)
                .accessibilityIdentifier("confidence_hint")
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }

    // MARK: - Edit Sheet

    private func startEditing(_ index: Int) {
        guard index < detections.count else { return }
        editText = detections[index].text
        editingIndex = index
    }

    private func editSheet(for index: Int) -> some View {
        NavigationStack {
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
                            detections[idx].markReaderConfirmed()
                            if let id = historyItemID {
                                HistoryManager.shared.updateDetections(id: id, detections: detections)
                            }
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
                    ForEach(Array(visibleLines.enumerated()), id: \.offset) { position, line in
                        let index = line.index
                        let det = line.detection
                        let isSelected = selectedIndex == index
                        let needsReread = edit.editor?.items.indices.contains(index) == true && edit.editor?.items[index].needsReread == true
                        let color = boxColor(for: index)

                        HStack(alignment: .top, spacing: 4) {
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(position + 1)")
                                    .font(.footnote.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundColor(KotenColor.shu)
                                    .frame(minWidth: 24, alignment: .trailing)

                                Text(det.text.isEmpty ? "---" : det.text)
                                    .font(.mincho(18, relativeTo: .body))
                                    .foregroundColor(det.text.isEmpty || needsReread ? KotenColor.inkSecondary : KotenColor.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if needsReread {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.caption)
                                        .foregroundColor(KotenColor.shu)
                                        .accessibilityLabel(Text("box_edit_pending"))
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedIndex = selectedIndex == index ? nil : index
                                }
                            }
                            .onLongPressGesture {
                                if !edit.isActive { startEditing(index) }
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text("\(position + 1): \(det.text)"))
                            .accessibilityAddTraits(.isButton)
                            .accessibilityIdentifier("detection_row_\(index)")
                            .accessibilityAction(named: Text("edit_text")) {
                                if !edit.isActive { startEditing(index) }
                            }

                            Button {
                                startEditing(index)
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.subheadline)
                                    .foregroundColor(KotenColor.inkSecondary)
                                    .frame(width: 40, height: 40)
                            }
                            .buttonStyle(.borderless)
                            .disabled(edit.isActive)
                            .accessibilityLabel(Text("edit_text"))
                            .accessibilityIdentifier("edit_detection_\(index)")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isSelected ? color.opacity(0.2) : Color.clear)
                        )
                        .id(index)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .padding(.bottom, 96) // room for the floating Copy button
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
            VStack(alignment: .leading, spacing: 12) {
                if isTranslating {
                    // Soft light passes over placeholder lines (1.2 s cycle) while translating.
                    VStack(alignment: .leading, spacing: 14) {
                        ShimmerLine(widthFraction: 0.92)
                        ShimmerLine(widthFraction: 0.8)
                        ShimmerLine(widthFraction: 0.86)
                        Text(String(localized: "translating", defaultValue: "翻訳中..."))
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(KotenColor.inkSecondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .transition(.opacity)
                } else if let translated = translatedText, !translated.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Button(action: startTranslation) {
                            Label(String(localized: "retranslate_button", defaultValue: "再翻訳"),
                                  systemImage: "arrow.clockwise")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .frame(minHeight: 40)
                        }
                        .buttonStyle(.kotenGlass)
                        .disabled(isTranslating)

                        Text(translated)
                            .font(.mincho(17, relativeTo: .body))
                            .lineSpacing(8)
                            .foregroundColor(KotenColor.ink)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .transition(.opacity)
                }

                if let error = translationError {
                    Text(error)
                        .font(.callout)
                        .foregroundColor(KotenColor.shu)
                        .padding(.horizontal, 20)
                }

                if translatedText == nil && !isTranslating {
                    VStack(spacing: 16) {
                        Image(systemName: "text.book.closed")
                            .font(.system(size: 36, weight: .light))
                            .foregroundColor(KotenColor.inkSecondary)
                            .accessibilityHidden(true)
                        Text(String(localized: "translation_empty", defaultValue: "現代語訳がまだありません"))
                            .font(.mincho(17, relativeTo: .body))
                            .foregroundColor(KotenColor.inkSecondary)
                        Button(action: startTranslation) {
                            Label(String(localized: "translate_button", defaultValue: "現代語訳"), systemImage: "sparkles")
                                .font(.headline)
                                .padding(.horizontal, 24)
                                .frame(minHeight: 48)
                        }
                        .buttonStyle(.kotenProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            }
            .padding(.bottom, 96)
            .animation(.easeInOut(duration: 0.2), value: isTranslating)
        }
    }

    // MARK: - Copy, toast, stamp

    /// Floating 朱 Copy button. Copies the text of the visible tab.
    private var copyButton: some View {
        Button(action: copyCurrentTab) {
            Label(String(localized: "copy", defaultValue: "Copy"), systemImage: "doc.on.doc")
                .font(.headline.weight(.heavy))
                .padding(.horizontal, 22)
                .frame(minHeight: 54)
        }
        .buttonStyle(.kotenProminent)
        .accessibilityLabel(Text("copy"))
        .accessibilityIdentifier("copy_button")
        .padding(.trailing, 20)
        .padding(.bottom, 16)
        .opacity(selectedTab == .translation && (translatedText ?? "").isEmpty ? 0 : 1)
    }

    private var copiedToast: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.caption.weight(.black))
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(KotenColor.shuFill))
            Text(String(localized: "copied_toast", defaultValue: "コピーしました"))
                .font(.headline)
                .foregroundColor(KotenColor.ink)
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 46)
        .kotenGlass(.regular, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("copied_toast")
    }

    /// 朱印 pressed when OCR finishes: 1.3 → 1.0 with ink spreading, about 250 ms,
    /// success haptic. With Reduce Motion it only fades in. Fades away after a moment.
    @ViewBuilder private var completionStamp: some View {
        if stampPhase > 0 {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(KotenColor.shuFill)
                    .frame(width: 64, height: 64)
                    .blur(radius: 8)
                    .opacity(stampPhase == 2 ? 0.3 : 0)
                    .scaleEffect(stampPhase == 2 ? 1.2 : 1)
                KotenStamp(size: 56)
            }
            .scaleEffect(stampPhase == 1 && !reduceMotion ? 1.3 : 1)
            .opacity(stampPhase == 1 ? (reduceMotion ? 0 : 0.5) : (stampPhase == 4 ? 0 : 1))
            .padding(10)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func playStampIfNeeded() {
        guard playCompletionStamp.wrappedValue else { return }
        playCompletionStamp.wrappedValue = false
        stampPhase = 1
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.12)) { stampPhase = 2 }
            KotenHaptics.notify(.success)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeOut(duration: 0.13)) { stampPhase = 3 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeIn(duration: 0.4)) { stampPhase = 4 }
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

    // MARK: - Box editing

    /// The lines being shown: the edit copy while editing, otherwise the saved result.
    private var shownDetections: [Detection] {
        edit.editor?.detections ?? detections
    }

    /// The lines on screen with their index in the full list. While editing boxes every line shows
    /// (the editor works on the whole list); otherwise lines below the confidence slider are left out.
    private var visibleLines: [(index: Int, detection: Detection)] {
        if edit.isActive { return shownDetections.enumerated().map { ($0.offset, $0.element) } }
        return ConfidenceFilter.visible(detections, threshold: confidenceThreshold)
    }

    /// The header count follows what is on screen (nil = all lines, or the editor reports its own).
    private func syncLineCount() {
        guard !edit.isActive else { return }
        let visible = ConfidenceFilter.visible(detections, threshold: confidenceThreshold).count
        editingLineCount.wrappedValue = visible == detections.count ? nil : visible
    }

    private func beginEditing() {
        showBoxes = true
        selectedTab = .ocr
        edit.begin(detections: detections,
                   imageSize: CGSize(width: image.width, height: image.height),
                   selected: selectedIndex)
    }

    private func cancelEditing() {
        edit.cancel()
        syncLineCount()
        selectedIndex = nil
    }

    private func startReread() {
        Task { await edit.reread(engine: ocrEngine, image: image, fallbackMode: ocrEngine.currentMode) }
    }

    /// Done: reads any boxes still waiting, then saves to the result and to history.
    private func finishEditing() {
        Task {
            if (edit.editor?.pendingCount ?? 0) > 0 {
                let ok = await edit.reread(engine: ocrEngine, image: image, fallbackMode: ocrEngine.currentMode)
                if !ok { return }
            }
            guard let edited = edit.finish() else { return }
            detections = edited
            syncLineCount()
            selectedIndex = nil
            if let id = historyItemID {
                HistoryManager.shared.updateDetections(id: id, detections: edited)
            }
        }
    }

    private var combinedText: String {
        ConfidenceFilter.text(detections, threshold: confidenceThreshold)
    }

    private func copyCurrentTab() {
        let text = selectedTab == .translation ? (translatedText ?? "") : combinedText
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        KotenHaptics.notify(.success)
        withAnimation(KotenMotion.spring(0.35, reduceMotion: reduceMotion)) { showCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeIn(duration: 0.2)) { showCopied = false }
        }
    }

    private func boxColor(for index: Int) -> Color {
        KotenColor.shu
    }
}

/// Places line-number tags at the start of their lines, just outside the box: above a
/// vertical line, left of a horizontal one. A tag is first sized to its line's width, so tags of
/// neighbouring lines stay apart however crowded the page is; on a dense page they are small
/// until the reader zooms in (tags zoom with the image). A tag much smaller than the page's
/// typical one (a thin side note) is then grown where it covers no other box or tag. When there
/// is no room before the image edge the tag goes inside the start of its box.
enum LineTagLayout {
    /// Clear space between a tag and its box. Not shrunk with small tags: the tag's rim and the
    /// box line would otherwise close it (two-digit tags, shrunk most, looked stuck to the box).
    static let gap: CGFloat = 3
    /// Regular tag height; the font is three quarters of the tag height.
    static let regularHeight: CGFloat = 12
    /// A tag on a thin line (傍書 and the like) is never smaller than this, so its number stays legible.
    /// Lines of a uniformly dense page are not "thin" (they are all alike) and keep the small tags that
    /// keep neighbours apart; the reader zooms in there.
    static let minimumLegibleHeight: CGFloat = 9
    /// A line is thin when it is under this share of the page's typical line thickness.
    static let thinShare: CGFloat = 0.6

    static func regularSize(for number: Int) -> CGSize {
        CGSize(width: CGFloat(8 + 5 * String(number).count), height: regularHeight)
    }

    /// Box outline width for a page: 8% of its typical line thickness (the median of the
    /// boxes' short sides), between 0.5 and 1.5 pt. A fixed 1.5 pt took a quarter of a
    /// 12 pt column.
    static func boxLineWidth(for rects: [CGRect]) -> CGFloat {
        let thickness = rects.map { min($0.width, $0.height) }.sorted()
        guard !thickness.isEmpty else { return 1.5 }
        return min(1.5, max(0.5, thickness[thickness.count / 2] * 0.08))
    }

    static func frames(for rects: [CGRect], in bounds: CGRect? = nil) -> [CGRect] {
        let area = bounds ?? CGRect(x: 0, y: 0, width: CGFloat.greatestFiniteMagnitude,
                                    height: CGFloat.greatestFiniteMagnitude)
        var tags = rects.enumerated().map { index, rect in
            let regular = regularSize(for: index + 1)
            let vertical = rect.height >= rect.width
            let scale = min(1, vertical ? rect.width / regular.width : rect.height / regular.height)
            return place(CGSize(width: regular.width * scale, height: regular.height * scale), at: rect, in: area)
        }
        // A thin line among regular ones (a side note, 傍書) would get a tag far smaller than its
        // neighbours'. Grow it toward the page's typical tag height, as far as it stays clear of
        // the other boxes and tags.
        let heights = tags.map(\.height).sorted()
        guard !heights.isEmpty else { return tags }
        let typical = heights[heights.count / 2]
        for (index, rect) in rects.enumerated() where tags[index].height < typical - 0.001 {
            let regular = regularSize(for: index + 1)
            let natural = tags[index].height
            for step in 0..<4 {
                let height = typical - (typical - natural) * CGFloat(step) / 4
                let size = CGSize(width: regular.width * height / regular.height, height: height)
                let tag = place(size, at: rect, in: area)
                // Half the box gap of clear space, so a grown tag never squeezes up against a neighbour.
                let room = tag.insetBy(dx: -gap / 2, dy: -gap / 2)
                let blocked = rects.indices.contains { other in
                    other != index && (rects[other].intersects(room) || tags[other].intersects(room))
                }
                // Only outside the box: a larger tag inside it would hide more of the first characters.
                if !blocked && !tag.intersects(rect) {
                    tags[index] = tag
                    break
                }
            }
        }
        // Last resort for thin lines (傍書): a floor on the tag size, even where it touches neighbours.
        // Their rim and slight transparency keep overlapping tags readable.
        let thickness = rects.map { min($0.width, $0.height) }.sorted()
        let typicalThickness = thickness[thickness.count / 2]
        for (index, rect) in rects.enumerated() where tags[index].height < minimumLegibleHeight - 0.001 {
            guard min(rect.width, rect.height) < typicalThickness * thinShare else { continue }
            let regular = regularSize(for: index + 1)
            let height = minimumLegibleHeight
            let size = CGSize(width: regular.width * height / regular.height, height: height)
            let base = place(size, at: rect, in: area)
            // Step the tag further out along the line's direction (up for a vertical line, left for a
            // horizontal one) while it would cover another box or tag; keep the first spot if none is clear.
            let vertical = rect.height >= rect.width
            var chosen = base
            for step in 0..<3 {
                let shift = CGFloat(step) * (height + 2)
                let candidate = vertical ? base.offsetBy(dx: 0, dy: -shift) : base.offsetBy(dx: -shift, dy: 0)
                guard area.contains(candidate) else { break }
                let blocked = rects.indices.contains { other in
                    other != index && (rects[other].intersects(candidate) || tags[other].intersects(candidate))
                }
                if !blocked { chosen = candidate; break }
            }
            tags[index] = chosen
        }
        return tags
    }

    /// Outside the start of the line, or inside it when there is no room before the image edge.
    private static func place(_ size: CGSize, at rect: CGRect, in area: CGRect) -> CGRect {
        let vertical = rect.height >= rect.width
        let outside = vertical
            ? CGRect(x: rect.midX - size.width / 2, y: rect.minY - gap - size.height,
                     width: size.width, height: size.height)
            : CGRect(x: rect.minX - gap - size.width, y: rect.midY - size.height / 2,
                     width: size.width, height: size.height)
        if area.contains(outside) { return outside }
        return vertical
            ? CGRect(x: rect.midX - size.width / 2, y: rect.minY + gap, width: size.width, height: size.height)
            : CGRect(x: rect.minX + gap, y: rect.midY - size.height / 2, width: size.width, height: size.height)
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


/// Placeholder line with a soft light passing over it (1.2 s cycle). Static with Reduce Motion.
private struct ShimmerLine: View {
    let widthFraction: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(KotenColor.mount)
                .overlay {
                    if !reduceMotion {
                        LinearGradient(colors: [.clear, KotenColor.washiCard.opacity(0.9), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.5)
                            .offset(x: phase * geo.size.width)
                    }
                }
                .clipShape(Capsule())
                .frame(width: geo.size.width * widthFraction)
        }
        .frame(height: 14)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = 1 }
        }
    }
}
