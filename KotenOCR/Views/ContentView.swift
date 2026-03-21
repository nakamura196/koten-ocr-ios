import SwiftUI
import PhotosUI
import Photos
import StoreKit

enum AppState {
    case camera
    case cropping
    case confirmCrop
    case processing
    case result
}

struct ContentView: View {
    @EnvironmentObject var ocrEngine: OCREngine
    @State private var appState: AppState = .camera
    @State private var capturedImage: CGImage?
    @State private var ocrResult: OCRResult?
    @State private var editableDetections: [Detection] = []
    @State private var errorMessage: String?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedDetectionIndex: Int?
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var processingTask: Task<Void, Never>?
    @State private var currentHistoryItemID: UUID?
    @State private var translatedText: String?
    @State private var cameFromHistory = false
    @State private var preCropImage: CGImage?
    @State private var croppedPreview: CGImage?
    @State private var cropSessionID = UUID()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue
    @AppStorage("saveToLibrary") private var saveToLibrary = false
    @AppStorage("ocrSuccessCount") private var ocrSuccessCount = 0
    @Environment(\.requestReview) private var requestReview

    private var appTheme: AppTheme {
        AppTheme(rawValue: appThemeRaw) ?? .system
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            if !hasCompletedOnboarding {
                loadingView
            } else {
                switch ocrEngine.state {
                case .uninitialized, .loading:
                    loadingView
                case .error(let msg):
                    errorView(msg)
                case .ready:
                    mainContent
                        .onAppear { loadTestImageIfNeeded() }
                }
            }
        }
        .preferredColorScheme(appTheme.colorScheme)
        .fullScreenCover(isPresented: Binding(
            get: { !hasCompletedOnboarding },
            set: { if $0 { hasCompletedOnboarding = false } }
        )) {
            OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showHistory) {
            HistoryListView { item in
                loadHistoryItem(item)
            }
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 0) {
            Spacer()
            Image("AppIconDisplay")
                .resizable()
                .frame(width: 120, height: 120)
                .cornerRadius(26)
                .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
            Text("KotenOCR")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .padding(.top, 16)
            Text(String(localized: "app_tagline", defaultValue: "くずし字をAIで読み取る"))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top, 4)
            Spacer()
            ProgressView()
                .padding(.bottom, 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("loading_models"))
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.yellow)
            Text(String(localized: "init_error", defaultValue: "Initialization Error"))
                .font(.headline)
                .foregroundColor(.primary)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ZStack {
            switch appState {
            case .camera:
                cameraView
            case .cropping:
                croppingView
            case .confirmCrop:
                confirmCropView
            case .processing:
                processingView
            case .result:
                resultView
            }
        }
    }

    // MARK: - Camera View

    private var cameraView: some View {
        ZStack {
            CameraView(onCapture: { cgImage in
                showCropping(cgImage, fromCamera: true)
            })
            .ignoresSafeArea()

            VStack {
                HStack {
                    Button(action: { showHistory = true }) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                    }
                    .accessibilityIdentifier("history_button")
                    .accessibilityLabel(Text("history_button"))

                    Spacer()

                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                    }
                    .accessibilityIdentifier("settings_button")
                    .accessibilityLabel(Text("settings_button"))
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()
                HStack(spacing: 40) {
                    // Gallery button
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .frame(width: 60, height: 60)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                    }
                    .accessibilityIdentifier("gallery_button")
                    .accessibilityLabel(Text("gallery_button"))
                    .onChange(of: selectedPhotoItem) { newItem in
                        loadPhotoItem(newItem)
                    }

                    Spacer()
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Cropping View

    private var croppingView: some View {
        Group {
            if let img = preCropImage {
                CropView(
                    image: img,
                    onCrop: { cropped in
                        croppedPreview = cropped
                        appState = .confirmCrop
                    },
                    onSkip: {
                        croppedPreview = img
                        appState = .confirmCrop
                    },
                    onCancel: {
                        preCropImage = nil
                        croppedPreview = nil
                        appState = .camera
                    }
                )
                .id(cropSessionID)
            }
        }
    }

    // MARK: - Confirm Crop View

    private var confirmCropView: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button(action: {
                        croppedPreview = nil
                        cropSessionID = UUID()
                        appState = .cropping
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text(String(localized: "retrim", defaultValue: "Re-crop"))
                        }
                        .foregroundColor(.primary)
                    }
                    Spacer()
                    Text(String(localized: "confirm_crop_title", defaultValue: "Confirm"))
                        .font(.headline)
                    Spacer()
                    Button(action: {
                        croppedPreview = nil
                        preCropImage = nil
                        appState = .camera
                    }) {
                        Text(String(localized: "cancel", defaultValue: "Cancel"))
                            .foregroundColor(.secondary)
                    }
                }
                .padding()

                Spacer()

                if let preview = croppedPreview {
                    Image(decorative: preview, scale: 1.0)
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(12)
                        .padding(.horizontal, 20)
                }

                Spacer()

                // OCR mode buttons
                ocrModeButtons
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
            }
        }
    }

    // MARK: - OCR Mode Buttons

    private var ocrModeButtons: some View {
        HStack(spacing: 16) {
            Button(action: {
                runOCRWithMode(.koten)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "scroll")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "run_ocr_koten", defaultValue: "古典籍 OCR"))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(String(localized: "ocr_mode_koten_short", defaultValue: "くずし字"))
                            .font(.caption2)
                            .opacity(0.8)
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.orange)
                .cornerRadius(12)
            }

            Button(action: {
                runOCRWithMode(.ndl)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "run_ocr_ndl", defaultValue: "近代 OCR"))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(String(localized: "ocr_mode_ndl_short", defaultValue: "活字・手書き"))
                            .font(.caption2)
                            .opacity(0.8)
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.blue)
                .cornerRadius(12)
            }
        }
    }

    private func runOCRWithMode(_ mode: OCRMode) {
        guard let img = croppedPreview else { return }
        croppedPreview = nil
        ocrEngine.switchMode(to: mode)
        processImage(img)
    }

    // MARK: - Processing View

    private var processingView: some View {
        VStack(spacing: 20) {
            if let image = capturedImage {
                Image(decorative: image, scale: 1.0)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
                    .cornerRadius(12)
            }
            ProgressView()
                .scaleEffect(1.5)
            Text(String(localized: "recognizing_text", defaultValue: "Recognizing text..."))
                .foregroundColor(.primary)
                .font(.headline)

            Button(action: cancelProcessing) {
                Text(String(localized: "cancel", defaultValue: "Cancel"))
                    .font(.subheadline)
                    .foregroundColor(.red)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }
            .accessibilityLabel(Text("cancel"))
        }
        .padding()
    }

    // MARK: - Result View

    private var resultView: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Button(action: {
                    if cameFromHistory {
                        resetToCamera()
                        showHistory = true
                    } else {
                        backFromResult()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text(cameFromHistory
                             ? String(localized: "history_title", defaultValue: "履歴")
                             : String(localized: "back", defaultValue: "Back"))
                    }
                    .foregroundColor(.primary)
                }
                .accessibilityIdentifier("back_button")
                .accessibilityLabel(Text("back"))
                Spacer()
                if preCropImage != nil && !cameFromHistory {
                    Button(action: retrimImage) {
                        HStack(spacing: 6) {
                            Image(systemName: "crop")
                            Text(String(localized: "retrim", defaultValue: "Re-crop"))
                        }
                        .foregroundColor(.primary)
                    }
                    .accessibilityLabel(Text("retrim"))
                }
            }
            .padding()
            .background(Color(.systemBackground).opacity(0.8))

            if let image = capturedImage {
                ResultOverlayView(
                    image: image,
                    detections: $editableDetections,
                    selectedIndex: $selectedDetectionIndex,
                    historyItemID: currentHistoryItemID,
                    translatedText: $translatedText,
                    onOpenSettings: { showSettings = true }
                )
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding()
            }
        }
    }

    // MARK: - Actions

    private func showCropping(_ cgImage: CGImage, fromCamera: Bool = false) {
        preCropImage = cgImage
        appState = .cropping

        // Save original capture to photo library if enabled (only for camera captures)
        if fromCamera && saveToLibrary {
            saveImageToLibrary(cgImage)
        }
    }

    private func saveImageToLibrary(_ cgImage: CGImage) {
        let uiImage = UIImage(cgImage: cgImage)
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: uiImage)
            }
        }
    }

    private func processImage(_ cgImage: CGImage) {
        capturedImage = cgImage
        appState = .processing
        errorMessage = nil
        cameFromHistory = false

        processingTask = Task {
            do {
                let result = try await ocrEngine.process(image: cgImage)
                await MainActor.run {
                    self.ocrResult = result
                    self.editableDetections = result.detections
                    // Inject dummy translation for screenshot automation
                    if let dummyTranslation = ProcessInfo.processInfo.environment["TEST_TRANSLATION_TEXT"],
                       !dummyTranslation.isEmpty {
                        self.translatedText = dummyTranslation
                    } else {
                        self.translatedText = nil
                    }
                    self.appState = .result

                    // Auto-save to history
                    HistoryManager.shared.save(
                        image: cgImage,
                        detections: result.detections,
                        text: result.text
                    )
                    self.currentHistoryItemID = HistoryManager.shared.items.first?.id

                    // Request review after 3rd and 10th successful OCR
                    self.ocrSuccessCount += 1
                    if self.ocrSuccessCount == 3 || self.ocrSuccessCount == 10 {
                        requestReview()
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.appState = .camera
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.appState = .result
                }
            }
        }
    }

    private func retrimImage() {
        capturedImage = nil
        ocrResult = nil
        editableDetections = []
        errorMessage = nil
        selectedDetectionIndex = nil
        translatedText = nil
        cropSessionID = UUID()
        appState = .cropping
    }

    private func cancelProcessing() {
        processingTask?.cancel()
        processingTask = nil
        appState = .camera
    }

    private func loadPhotoItem(_ item: PhotosPickerItem?) {
        guard let item = item else { return }
        selectedPhotoItem = nil
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data),
               let cgImage = uiImage.normalizedCGImage {
                await MainActor.run { showCropping(cgImage) }
            }
        }
    }

    private func loadHistoryItem(_ item: HistoryItem) {
        guard let data = try? Data(contentsOf: item.imagePath),
              let uiImage = UIImage(data: data),
              let cgImage = uiImage.normalizedCGImage else { return }

        capturedImage = cgImage
        editableDetections = item.detections
        ocrResult = OCRResult(
            detections: editableDetections,
            text: item.text
        )
        selectedDetectionIndex = nil
        errorMessage = nil
        currentHistoryItemID = item.id
        translatedText = item.translatedText
        cameFromHistory = true
        appState = .result
    }

    /// Load a test image from path specified via launch argument (for UI test screenshot automation)
    private func loadTestImageIfNeeded() {
        guard appState == .camera,
              let testImagePath = ProcessInfo.processInfo.environment["TEST_IMAGE_PATH"],
              !testImagePath.isEmpty else { return }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: testImagePath)),
              let uiImage = UIImage(data: data),
              let cgImage = uiImage.normalizedCGImage else { return }

        // Directly start processing (skip crop for automation)
        processImage(cgImage)
    }

    private func backFromResult() {
        if let img = capturedImage {
            // Go back to confirm screen with the same image
            croppedPreview = img
            ocrResult = nil
            editableDetections = []
            selectedDetectionIndex = nil
            processingTask = nil
            translatedText = nil
            appState = .confirmCrop
        } else {
            resetToCamera()
        }
    }

    private func resetToCamera() {
        appState = .camera
        capturedImage = nil
        ocrResult = nil
        editableDetections = []
        errorMessage = nil
        selectedPhotoItem = nil
        selectedDetectionIndex = nil
        processingTask = nil
        currentHistoryItemID = nil
        translatedText = nil
        cameFromHistory = false
        preCropImage = nil
        croppedPreview = nil
    }

}
