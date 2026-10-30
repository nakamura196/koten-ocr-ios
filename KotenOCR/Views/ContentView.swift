import SwiftUI
import PhotosUI
import Photos
import StoreKit
import AVFoundation

enum AppState {
    case home
    case camera
    case cropping
    case confirmCrop
    case processing
    case result
}

struct ContentView: View {
    @EnvironmentObject var ocrEngine: OCREngine
    @State private var appState: AppState = ContentView.initialAppState()
    @State private var capturedImage: CGImage?
    @State private var ocrResult: OCRResult?
    @State private var editableDetections: [Detection] = []
    @State private var editingLineCount: Int?
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
    @State private var showScanner = false
    @State private var tiltHintShowing = false
    @State private var croppedPreview: CGImage?
    @State private var cropSessionID = UUID()
    @State private var testImageLoadCount = 0
    // Design: launch, scanning, guidance
    @State private var launchAnimationDone = false
    @State private var scanProgress: Float = 0
    @State private var scanReveal: [Detection] = []
    @State private var scanRevealCount = 0
    @State private var scanToken = UUID()
    @State private var playCompletionStamp = false
    @State private var isStartingOCR = false
    @State private var selectedOCRMode: OCRMode = .koten
    @State private var cameraAuth: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var showShutterCoach = false
    @Namespace private var brandNamespace
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue
    @AppStorage("saveToLibrary") private var saveToLibrary = false
    @AppStorage("ocrSuccessCount") private var ocrSuccessCount = 0
    /// The full seal-stamp launch plays once; later launches use the short version.
    @AppStorage("hasSeenLaunchStamp") private var hasSeenLaunchStamp = false
    @Environment(\.requestReview) private var requestReview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Home is the default start screen. Screenshot/test automation (TEST_IMAGE_PATH set,
    /// or `-skipHome YES`) goes straight to the camera state as before.
    private static func initialAppState() -> AppState {
        let env = ProcessInfo.processInfo.environment
        if let path = env["TEST_IMAGE_PATH"], !path.isEmpty { return .camera }
        if UserDefaults.standard.bool(forKey: "skipHome") { return .camera }
        return .home
    }

    private var appTheme: AppTheme {
        AppTheme(rawValue: appThemeRaw) ?? .system
    }

    private var isEngineReady: Bool {
        if case .ready = ocrEngine.state { return true }
        return false
    }

    var body: some View {
        ZStack {
            WashiBackground()

            if !hasCompletedOnboarding {
                LaunchView(namespace: brandNamespace, fullStamp: false, showsProgress: false, onFinished: {})
            } else if case .error(let msg) = ocrEngine.state {
                errorView(msg)
            } else if !isEngineReady || (!launchAnimationDone && appState == .home) {
                LaunchView(namespace: brandNamespace, fullStamp: !hasSeenLaunchStamp,
                           showsProgress: !isEngineReady) {
                    hasSeenLaunchStamp = true
                    launchAnimationDone = true
                }
            } else {
                mainContent
                    .onAppear { loadTestImageIfNeeded() }
                    .onChange(of: appState) { newState in
                        if newState == .camera {
                            loadSecondTestImageIfNeeded()
                        }
                    }
            }
        }
        .animation(KotenMotion.spring(0.45, reduceMotion: reduceMotion), value: launchAnimationDone)
        .animation(.easeOut(duration: 0.3), value: isEngineReady)
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
            HistoryListView(onSelect: { item in
                loadHistoryItem(item)
            }, onStartCamera: {
                resetToCamera()
            })
        }
        .onReceive(ocrEngine.$progress) { value in
            // The engine reports 1.0 while idle; only follow values from the running scan.
            guard appState == .processing, scanReveal.isEmpty, value < 1 else { return }
            scanProgress = max(scanProgress, value)
        }
        .onChange(of: scenePhase) { phase in
            // Coming back from the Settings app after allowing the camera.
            if phase == .active { cameraAuth = AVCaptureDevice.authorizationStatus(for: .video) }
        }
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(KotenColor.shu)
                .accessibilityHidden(true)
            Text(String(localized: "init_error", defaultValue: "Initialization Error"))
                .font(.mincho(22, relativeTo: .title2, bold: true))
                .foregroundColor(KotenColor.ink)
            Text(message)
                .font(.callout)
                .foregroundColor(KotenColor.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ZStack {
            switch appState {
            case .home:
                HomeView(
                    selectedPhotoItem: $selectedPhotoItem,
                    onCamera: { appState = .camera },
                    onHistory: { showHistory = true },
                    onSettings: { showSettings = true },
                    onOpenHistoryItem: { item in loadHistoryItem(item) },
                    brandNamespace: brandNamespace
                )
                .transition(.opacity)
            case .camera:
                cameraView
                    .transition(KotenMotion.screenTransition(reduceMotion: reduceMotion))
            case .cropping:
                croppingView
                    .transition(KotenMotion.screenTransition(reduceMotion: reduceMotion))
            case .confirmCrop:
                confirmCropView
                    .transition(.opacity)
            case .processing:
                processingView
                    .transition(.opacity)
            case .result:
                resultView
                    .transition(KotenMotion.rise(24, reduceMotion: reduceMotion))
            }
        }
        .animation(KotenMotion.spring(0.35, reduceMotion: reduceMotion), value: appState)
        .onChange(of: selectedPhotoItem) { newItem in
            loadPhotoItem(newItem)
        }
    }

    // MARK: - Camera View

    private var cameraDenied: Bool { cameraAuth == .denied || cameraAuth == .restricted }

    private var cameraView: some View {
        ZStack {
            CameraView(onCapture: { cgImage in
                CaptureMode.camera.save()
                showCropping(cgImage, fromCamera: true)
            })
            .ignoresSafeArea()

            // 朱 corners: where to put the page. Content side, so the same on every iOS.
            ScanCorners(length: 34, radius: 4)
                .stroke(KotenColor.shu, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .padding(.horizontal, 40)
                .padding(.top, 120)
                .padding(.bottom, 190) // stays clear of the flash and shutter buttons
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Button(action: { appState = .home }) {
                        KotenIconLabel(systemName: "house")
                    }
                    .buttonStyle(.kotenCameraCircle)
                    .accessibilityIdentifier("home_button")
                    .accessibilityLabel(Text("home_button"))

                    Button(action: { showHistory = true }) {
                        KotenIconLabel(systemName: "clock.arrow.circlepath")
                    }
                    .buttonStyle(.kotenCameraCircle)
                    .accessibilityIdentifier("history_button")
                    .accessibilityLabel(Text("history_button"))

                    Spacer()

                    Button(action: { showSettings = true }) {
                        KotenIconLabel(systemName: "gearshape")
                    }
                    .buttonStyle(.kotenCameraCircle)
                    .accessibilityIdentifier("settings_button")
                    .accessibilityLabel(Text("settings_button"))
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // Level guide above; the frame hint gives way while the tilt hint is shown.
                if !showScanner {
                    LevelGuideView(onTryScanner: DocumentScannerView.isSupported ? { openScanner() } : nil,
                                   isHintShowing: $tiltHintShowing)
                }

                if !tiltHintShowing {
                    Text("camera_frame_hint")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .kotenGlass(.onCamera, in: Capsule())
                        .padding(.horizontal, 40)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                Spacer()

                HStack {
                    // Gallery button, level with the (UIKit) shutter: shutter centre is 65pt above the safe area.
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        KotenIconLabel(systemName: "photo.on.rectangle", size: 56)
                    }
                    .buttonStyle(.kotenCameraCircle)
                    .accessibilityIdentifier("gallery_button")
                    .accessibilityLabel(Text("gallery_button"))
                    Spacer()

                    if DocumentScannerView.isSupported {
                        Button(action: openScanner) {
                            KotenIconLabel(systemName: "doc.viewfinder", size: 56)
                        }
                        .buttonStyle(.kotenCameraCircle)
                        .accessibilityIdentifier("scan_document_button")
                        .accessibilityLabel(Text(String(localized: "scan_document", defaultValue: "書類スキャン")))
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 37)
            }

            if showShutterCoach && !cameraDenied && !showScanner {
                ZStack(alignment: .bottom) {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    CoachBubble(text: String(localized: "coach_shutter", defaultValue: "ここを押して撮影"), pointer: .down)
                        .padding(.horizontal, 40)
                        .padding(.bottom, 108)
                }
                // A touch anywhere dismisses the one-time hint.
                .contentShape(Rectangle())
                .onTapGesture { dismissShutterCoach() }
                .transition(.opacity)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("coach_shutter")
            }

            if cameraDenied {
                CameraDeniedView(selectedPhotoItem: $selectedPhotoItem, onHome: { appState = .home })
                    .transition(KotenMotion.rise(16, reduceMotion: reduceMotion))
            }
        }
        .onAppear {
            cameraAuth = AVCaptureDevice.authorizationStatus(for: .video)
            if cameraDenied { KotenHaptics.notify(.warning) }
            if CaptureMode.load() == .scan && DocumentScannerView.isSupported && !cameraDenied {
                // The scanner opens by itself; the shutter hint waits until the camera is really shown.
                openScanner()
            } else {
                startShutterCoachIfNeeded()
            }
        }
        .onDisappear { dismissShutterCoach() }
        .animation(.easeInOut(duration: 0.15), value: tiltHintShowing)
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScannerView(
                onScan: { cg in
                    showScanner = false
                    CaptureMode.scan.save()
                    showCropping(cg, fromCamera: true)
                },
                onCancel: {
                    showScanner = false
                    CaptureMode.camera.save()
                    startShutterCoachIfNeeded()
                }
            )
            .ignoresSafeArea()
        }
    }

    /// Screenshot/demo automation loads images itself; hints would cover the screenshots.
    private var isAutomatedRun: Bool {
        if let path = ProcessInfo.processInfo.environment["TEST_IMAGE_PATH"], !path.isEmpty { return true }
        return false
    }

    private func startShutterCoachIfNeeded() {
        guard !CoachMark.shutter.isShown, !isAutomatedRun, !showScanner, !cameraDenied else { return }
        withAnimation(.easeOut(duration: 0.3).delay(0.5)) { showShutterCoach = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { dismissShutterCoach() }
    }

    private func dismissShutterCoach() {
        guard showShutterCoach else { return }
        CoachMark.shutter.markShown()
        withAnimation(.easeOut(duration: 0.2)) { showShutterCoach = false }
    }

    // MARK: - Cropping View

    private var croppingView: some View {
        Group {
            if let img = preCropImage {
                CropView(
                    image: img,
                    onCrop: { cropped, source in
                        // Keep any rotation done in the crop screen for "Re-crop"
                        preCropImage = source
                        croppedPreview = cropped
                        appState = .confirmCrop
                    },
                    onSkip: { displayed in
                        preCropImage = displayed
                        croppedPreview = displayed
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
            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button(action: {
                        croppedPreview = nil
                        cropSessionID = UUID()
                        appState = .cropping
                    }) {
                        KotenBackLabel(title: String(localized: "retrim", defaultValue: "Re-crop"))
                    }
                    .buttonStyle(.kotenGlass)
                    .accessibilityIdentifier("retrim_button")
                    Spacer(minLength: 8)
                    Button(action: {
                        // Also drops the earlier result kept for "Back" (it holds the deskewed page)
                        resetToCamera()
                    }) {
                        Text(String(localized: "cancel", defaultValue: "Cancel"))
                            .font(.body.weight(.semibold))
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.kotenGlass)
                }
                .overlay {
                    if !typeSize.isAccessibilitySize {
                        Text(String(localized: "confirm_crop_title", defaultValue: "Confirm"))
                            .font(.mincho(18, relativeTo: .headline, bold: true))
                            .foregroundColor(KotenColor.ink)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)

                Spacer(minLength: 12)

                if let preview = croppedPreview {
                    Image(decorative: preview, scale: 1.0)
                        .resizable()
                        .scaledToFit()
                        .kotenMount()
                        .padding(.horizontal, 20)
                }

                Spacer(minLength: 12)

                ocrModeToolbar
                    .padding(.horizontal, 12)
                    .padding(.bottom, 16)
                    .disabled(ocrEngine.isLoadingModels || isStartingOCR)
            }

            if ocrEngine.isLoadingModels {
                Color.black.opacity(0.3).ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text(String(localized: "loading_models", defaultValue: "Loading models..."))
                        .font(.subheadline)
                        .foregroundColor(KotenColor.ink)
                }
                .padding(24)
                .kotenGlass(.regular, in: RoundedRectangle(cornerRadius: 20))
            }
        }
        .onAppear {
            selectedOCRMode = ocrEngine.currentMode
            isStartingOCR = false
        }
    }

    // MARK: - OCR Mode Toolbar

    /// Glass toolbar: text type switch (古典籍 / 近代) and the 朱 "Read" button.
    private var ocrModeToolbar: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            HStack(spacing: 0) {
                modeSegment(.koten, title: String(localized: "ocr_mode_koten", defaultValue: "古典籍"),
                            subtitle: String(localized: "ocr_mode_koten_short", defaultValue: "くずし字"),
                            id: "koten_ocr_button")
                modeSegment(.ndl, title: String(localized: "ocr_mode_ndl", defaultValue: "近代"),
                            subtitle: String(localized: "ocr_mode_ndl_short", defaultValue: "活字・手書き"),
                            id: "ndl_ocr_button")
            }
            .padding(3)
            .background(Capsule().fill(KotenColor.ink.opacity(0.08)))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("ocr_mode_picker"))

            Button(action: { runOCRWithMode(selectedOCRMode) }) {
                HStack(spacing: 8) {
                    if isStartingOCR {
                        ProgressView().tint(.white)
                        Text("reading_in_progress")
                    } else {
                        Text("run_ocr")
                    }
                }
                .font(.headline.weight(.heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 22)
                .frame(minWidth: 120, minHeight: 50)
                .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil)
            }
            .buttonStyle(.kotenProminent)
            .accessibilityIdentifier("run_ocr_button")
        }
        .padding(10)
        .kotenGlass(.regular, in: RoundedRectangle(cornerRadius: 36, style: .continuous))
        .animation(KotenMotion.spring(0.3, reduceMotion: reduceMotion), value: isStartingOCR)
    }

    private func modeSegment(_ mode: OCRMode, title: String, subtitle: String, id: String) -> some View {
        let selected = selectedOCRMode == mode
        return Button {
            withAnimation(KotenMotion.spring(0.3, reduceMotion: reduceMotion)) { selectedOCRMode = mode }
        } label: {
            VStack(spacing: 1) {
                Text(title).font(.subheadline.weight(.bold))
                Text(subtitle).font(.caption2).opacity(0.8)
            }
            .foregroundColor(selected ? KotenColor.ink : KotenColor.inkSecondary)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                if selected {
                    Capsule().fill(KotenColor.washiCard)
                        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func runOCRWithMode(_ mode: OCRMode) {
        guard let img = croppedPreview, !isStartingOCR else { return }
        isStartingOCR = true
        Task {
            do {
                try await ocrEngine.switchMode(to: mode)
            } catch {
                await MainActor.run {
                    // Drop any image left over from an earlier scan so it is not shown next to the error
                    self.isStartingOCR = false
                    self.croppedPreview = nil
                    self.capturedImage = nil
                    self.ocrResult = nil
                    self.editableDetections = []
                    self.currentHistoryItemID = nil
                    self.errorMessage = Self.userFacingMessage(for: error, modelLoading: true)
                    self.appState = .result
                }
                return
            }
            await MainActor.run {
                self.croppedPreview = nil
                processImage(img)
            }
        }
    }

    // MARK: - Processing View

    private var processingView: some View {
        Group {
            if let image = capturedImage {
                ScanningView(
                    image: image,
                    progress: scanProgress,
                    detections: scanReveal,
                    revealedCount: scanRevealCount,
                    onCancel: cancelProcessing
                )
            }
        }
    }

    // MARK: - Result View

    private var resultView: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack(spacing: 10) {
                Button(action: {
                    if cameFromHistory {
                        resetToCamera()
                        showHistory = true
                    } else {
                        backFromResult()
                    }
                }) {
                    KotenBackLabel(title: cameFromHistory
                                   ? String(localized: "history_title", defaultValue: "履歴")
                                   : String(localized: "back", defaultValue: "Back"))
                }
                .buttonStyle(.kotenGlass)
                .accessibilityIdentifier("back_button")
                .accessibilityLabel(Text("back"))
                Spacer(minLength: 8)
                if preCropImage != nil && !cameFromHistory {
                    Button(action: retrimImage) {
                        KotenIconLabel(systemName: "crop")
                    }
                    .buttonStyle(.kotenGlassCircle)
                    .accessibilityLabel(Text("retrim"))
                }
            }
            .overlay {
                if errorMessage == nil && !editableDetections.isEmpty && !typeSize.isAccessibilitySize {
                    Text(String(format: String(localized: "lines_count_format", defaultValue: "%d 行"), editingLineCount ?? editableDetections.count))
                        .font(.mincho(18, relativeTo: .headline, bold: true))
                        .foregroundColor(KotenColor.ink)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 4)

            if let error = errorMessage {
                errorPanel(error)
            } else if let image = capturedImage, editableDetections.isEmpty, !cameFromHistory {
                noLinesPanel(image)
            } else if let image = capturedImage {
                ResultOverlayView(
                    image: image,
                    detections: $editableDetections,
                    selectedIndex: $selectedDetectionIndex,
                    historyItemID: currentHistoryItemID,
                    translatedText: $translatedText,
                    onOpenSettings: { showSettings = true },
                    playCompletionStamp: $playCompletionStamp,
                    editingLineCount: $editingLineCount
                )
            }
        }
        .washiBackground()
    }

    private func errorPanel(_ message: String) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                ZStack {
                    Circle().fill(KotenColor.washiCard)
                    Circle().stroke(KotenColor.shu, lineWidth: 4)
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 48, weight: .light))
                        .foregroundColor(KotenColor.shu)
                }
                .frame(width: 110, height: 110)
                .accessibilityHidden(true)
                .padding(.top, 60)
                Text(message)
                    .font(.mincho(18, relativeTo: .body))
                    .foregroundColor(KotenColor.ink)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .accessibilityIdentifier("ocr_error_message")
            }
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) { retakeButton }
        .onAppear { KotenHaptics.notify(.warning) }
    }

    /// Storyboard e: OCR finished but found no lines. Tips, then one big Retake button.
    private func noLinesPanel(_ image: CGImage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Image(decorative: image, scale: 1.0)
                    .resizable()
                    .scaledToFit()
                    .grayscale(0.6)
                    .frame(maxHeight: 200)
                    .frame(maxWidth: .infinity)
                    .kotenMount()
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                VStack(alignment: .leading, spacing: 14) {
                    Text("no_lines_title")
                        .font(.mincho(24, relativeTo: .title2, bold: true))
                        .foregroundColor(KotenColor.ink)
                        .accessibilityIdentifier("ocr_error_message")
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(["no_lines_tip_page", "no_lines_tip_light", "no_lines_tip_modern"], id: \.self) { key in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("・")
                                Text(LocalizedStringKey(key))
                            }
                            .font(.callout.weight(.semibold))
                            .foregroundColor(KotenColor.inkSecondary)
                        }
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 24)
            }
        }
        .safeAreaInset(edge: .bottom) { retakeButton }
        .onAppear { KotenHaptics.notify(.warning) }
    }

    private var retakeButton: some View {
        Button(action: resetToCamera) {
            Text(String(localized: "ocr_error_retake", defaultValue: "撮り直す"))
                .font(.title3.weight(.heavy))
                .frame(maxWidth: .infinity, minHeight: 58)
        }
        .buttonStyle(.kotenProminent)
        .accessibilityIdentifier("retake_button")
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    // MARK: - Actions

    private func openScanner() {
        CaptureMode.scan.save()
        showScanner = true
    }

    private func showCropping(_ cgImage: CGImage, fromCamera: Bool = false) {
        // A new page starts: drop every image of the previous one first, so two full-size pages
        // are never held at once (the "crashes on the 2nd image" report).
        releasePreviousPage()
        preCropImage = ImageIntake.limit(cgImage)
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

    /// Releases the images and results of the page shown before (OCR result, deskewed image,
    /// crop preview, any unfinished run).
    private func releasePreviousPage() {
        processingTask?.cancel()
        processingTask = nil
        capturedImage = nil
        ocrResult = nil
        editableDetections = []
        selectedDetectionIndex = nil
        errorMessage = nil
        translatedText = nil
        currentHistoryItemID = nil
        cameFromHistory = false
        croppedPreview = nil
        preCropImage = nil
    }

    private func processImage(_ cgImage: CGImage) {
        processingTask?.cancel()
        ocrResult = nil
        editableDetections = []
        capturedImage = cgImage
        scanProgress = 0
        scanReveal = []
        scanRevealCount = 0
        scanToken = UUID()
        playCompletionStamp = false
        isStartingOCR = false
        appState = .processing
        errorMessage = nil
        cameFromHistory = false
        currentHistoryItemID = nil

        processingTask = Task {
            do {
                let result = try await ocrEngine.process(image: cgImage)
                // Boxes refer to the (possibly deskewed) image OCR ran on
                let processedImage = result.image ?? cgImage
                await MainActor.run {
                    // A cancelled run (Cancel, or a newer page) must not overwrite the current screen.
                    guard !Task.isCancelled else { return }
                    self.capturedImage = processedImage
                    self.ocrResult = result
                    self.editableDetections = result.detections
                    // Inject dummy translation for screenshot automation
                    if let dummyTranslation = ProcessInfo.processInfo.environment["TEST_TRANSLATION_TEXT"],
                       !dummyTranslation.isEmpty {
                        self.translatedText = dummyTranslation
                    } else {
                        self.translatedText = nil
                    }
                    self.finishScan(with: result.detections)

                    // Auto-save to history
                    self.currentHistoryItemID = HistoryManager.shared.save(
                        image: processedImage,
                        detections: result.detections,
                        text: result.text
                    )

                    // Request review after 3rd and 10th successful OCR
                    self.ocrSuccessCount += 1
                    if self.ocrSuccessCount == 3 || self.ocrSuccessCount == 10 {
                        requestReview()
                    }
                }
            } catch is CancellationError {
                // Whoever cancelled (Cancel button, new page) has already set the screen.
            } catch {
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.errorMessage = Self.userFacingMessage(for: error, modelLoading: false)
                    self.appState = .result
                }
            }
        }
    }

    /// OCR errors are English developer strings. Show a localized, readable message instead.
    private static func userFacingMessage(for error: Error, modelLoading: Bool) -> String {
        print("OCR error: \(error)")
        if modelLoading {
            return String(localized: "ocr_error_model", defaultValue: "文字認識の準備に失敗しました。アプリを再起動してもう一度お試しください。")
        }
        return String(localized: "ocr_error_generic", defaultValue: "文字を読み取れませんでした。画像を撮り直してもう一度お試しください。")
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

    /// Storyboard c, last step: the found lines appear one by one in reading order
    /// (about 40 ms each, at most ~0.8 s in total), then the result opens with the 朱 stamp.
    private func finishScan(with detections: [Detection]) {
        let token = UUID()
        scanToken = token
        scanProgress = 1
        guard !detections.isEmpty, !reduceMotion else {
            showScanResult()
            return
        }
        scanReveal = detections
        scanRevealCount = 0
        let step = min(0.04, 0.8 / Double(detections.count))
        for i in 1...detections.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + step * Double(i)) {
                guard scanToken == token, appState == .processing else { return }
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { scanRevealCount = i }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + step * Double(detections.count) + 0.45) {
            guard scanToken == token, appState == .processing else { return }
            showScanResult()
        }
    }

    private func showScanResult() {
        playCompletionStamp = !editableDetections.isEmpty
        appState = .result
        scanReveal = []
        scanRevealCount = 0
        if !editableDetections.isEmpty {
            UIAccessibility.post(notification: .announcement,
                                 argument: String(localized: "ocr_finished_announcement", defaultValue: "読み取りが完了しました"))
        }
    }

    private func cancelProcessing() {
        scanToken = UUID()
        scanReveal = []
        scanRevealCount = 0
        processingTask?.cancel()
        processingTask = nil
        capturedImage = nil
        ocrResult = nil
        editableDetections = []
        appState = .camera
    }

    private func loadPhotoItem(_ item: PhotosPickerItem?) {
        guard let item = item else { return }
        selectedPhotoItem = nil
        Task {
            // Decode straight to ≤ ImageIntake.maxLongSide px: library photos from recent iPhones
            // are 24 or 48 MP.
            if let data = try? await item.loadTransferable(type: Data.self),
               let cgImage = ImageIntake.decode(data) {
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

    /// Load a test image from path specified via environment variable (for UI test automation).
    /// When TEST_SHOW_CROP is "YES", enters the crop flow instead of processing directly.
    private func loadTestImageIfNeeded() {
        guard appState == .camera, testImageLoadCount == 0,
              let testImagePath = ProcessInfo.processInfo.environment["TEST_IMAGE_PATH"],
              !testImagePath.isEmpty else { return }

        testImageLoadCount = 1

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: testImagePath)),
              let cgImage = ImageIntake.decode(data) else { return }

        if ProcessInfo.processInfo.environment["TEST_SHOW_CROP"] == "YES" {
            showCropping(cgImage)
        } else {
            processImage(cgImage)
        }
    }

    /// Load a second test image when returning to camera (for combined demo videos).
    /// Activated by TEST_SECOND_IMAGE_PATH env var; always enters the crop flow.
    private func loadSecondTestImageIfNeeded() {
        guard testImageLoadCount == 1,
              let secondPath = ProcessInfo.processInfo.environment["TEST_SECOND_IMAGE_PATH"],
              !secondPath.isEmpty else { return }

        testImageLoadCount = 2

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: secondPath)),
              let cgImage = ImageIntake.decode(data) else { return }

        showCropping(cgImage)
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
