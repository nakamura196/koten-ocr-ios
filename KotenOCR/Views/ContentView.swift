import SwiftUI
import PhotosUI

enum AppState {
    case camera
    case processing
    case result
}

struct ContentView: View {
    @EnvironmentObject var ocrEngine: OCREngine
    @State private var appState: AppState = .camera
    @State private var capturedImage: CGImage?
    @State private var ocrResult: OCRResult?
    @State private var errorMessage: String?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedDetectionIndex: Int?
    @State private var showSettings = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch ocrEngine.state {
            case .uninitialized, .loading:
                loadingView
            case .error(let msg):
                errorView(msg)
            case .ready:
                mainContent
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { !hasCompletedOnboarding },
            set: { if $0 { hasCompletedOnboarding = false } }
        )) {
            OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)
            Text("Loading OCR Models...")
                .foregroundColor(.white)
                .font(.headline)
            ProgressView(value: ocrEngine.progress)
                .progressViewStyle(.linear)
                .frame(width: 200)
                .tint(.blue)
            Text("\(Int(ocrEngine.progress * 100))%")
                .foregroundColor(.gray)
                .font(.caption)
        }
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.yellow)
            Text("Initialization Error")
                .font(.headline)
                .foregroundColor(.white)
            Text(message)
                .font(.caption)
                .foregroundColor(.gray)
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
                processImage(cgImage)
            })
            .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                    }
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
                .tint(.white)
            Text("Recognizing text...")
                .foregroundColor(.white)
                .font(.headline)
        }
        .padding()
    }

    // MARK: - Result View

    private var resultView: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Button(action: { resetToCamera() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundColor(.white)
                }
                Spacer()
            }
            .padding()
            .background(Color.black.opacity(0.8))

            if let image = capturedImage, let result = ocrResult {
                ResultOverlayView(
                    image: image,
                    detections: result.detections,
                    selectedIndex: $selectedDetectionIndex
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

    private func processImage(_ cgImage: CGImage) {
        capturedImage = cgImage
        appState = .processing
        errorMessage = nil

        Task {
            do {
                let result = try await ocrEngine.process(image: cgImage)
                await MainActor.run {
                    self.ocrResult = result
                    self.appState = .result
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.appState = .result
                }
            }
        }
    }

    private func loadPhotoItem(_ item: PhotosPickerItem?) {
        guard let item = item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let provider = CGDataProvider(data: data as CFData),
               let cgImage = CGImage(
                   jpegDataProviderSource: provider,
                   decode: nil, shouldInterpolate: true,
                   intent: .defaultIntent
               ) ?? CGImage(
                   pngDataProviderSource: provider,
                   decode: nil, shouldInterpolate: true,
                   intent: .defaultIntent
               ) {
                await MainActor.run { processImage(cgImage) }
            } else if let data = try? await item.loadTransferable(type: Data.self) {
                // Fallback: use UIImage
                #if canImport(UIKit)
                if let uiImage = UIImage(data: data), let cgImage = uiImage.cgImage {
                    await MainActor.run { processImage(cgImage) }
                }
                #endif
            }
        }
    }

    private func resetToCamera() {
        appState = .camera
        capturedImage = nil
        ocrResult = nil
        errorMessage = nil
        selectedPhotoItem = nil
        selectedDetectionIndex = nil
    }

}
