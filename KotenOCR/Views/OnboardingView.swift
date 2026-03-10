import SwiftUI
import AVFoundation

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentPage = 0
    @State private var cameraStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack {
                TabView(selection: $currentPage) {
                    introPage.tag(0)
                    cameraPermissionPage.tag(1)
                    howToUsePage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                if currentPage == 2 {
                    Button(action: {
                        hasCompletedOnboarding = true
                    }) {
                        Text(String(localized: "onboarding_start", defaultValue: "はじめる"))
                            .font(.headline)
                            .foregroundColor(Color(.systemBackground))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.primary)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
                    .accessibilityLabel(Text("onboarding_start"))
                }
            }
        }
    }

    // MARK: - Page 1: Intro

    private var introPage: some View {
        VStack(spacing: 24) {
            Spacer()
            Image("AppIconDisplay")
                .resizable()
                .frame(width: 100, height: 100)
                .cornerRadius(22)
                .accessibilityHidden(true)
            Text("KotenOCR")
                .font(.largeTitle)
                .bold()
                .foregroundColor(.primary)
            Text(String(localized: "onboarding_intro", defaultValue: "古典籍・くずし字の文字認識アプリ。\nカメラで撮影するだけで、くずし字をテキストに変換します。"))
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
    }

    // MARK: - Page 2: Camera Permission

    private var cameraPermissionPage: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: cameraStatus == .authorized ? "checkmark.circle.fill" : "camera.fill")
                .font(.system(size: 60))
                .foregroundColor(cameraStatus == .authorized ? .green : .primary)
                .accessibilityHidden(true)
            Text(String(localized: "onboarding_camera_title", defaultValue: "カメラへのアクセス"))
                .font(.title2)
                .bold()
                .foregroundColor(.primary)
            Text(String(localized: "onboarding_camera_description", defaultValue: "古典籍の文字を認識するために、\nカメラへのアクセスを許可してください。"))
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            switch cameraStatus {
            case .authorized:
                Text(String(localized: "onboarding_camera_granted", defaultValue: "カメラは許可済みです"))
                    .font(.subheadline)
                    .foregroundColor(.green)
            case .denied, .restricted:
                VStack(spacing: 12) {
                    Text(String(localized: "onboarding_camera_denied", defaultValue: "カメラが許可されていません"))
                        .font(.subheadline)
                        .foregroundColor(.red)
                    Button(action: openSettings) {
                        Text(String(localized: "camera_open_settings", defaultValue: "設定を開く"))
                            .font(.headline)
                            .foregroundColor(Color(.systemBackground))
                            .padding(.horizontal, 32)
                            .padding(.vertical, 12)
                            .background(Color.primary)
                            .cornerRadius(10)
                    }
                    .accessibilityLabel(Text("camera_open_settings"))
                }
            default:
                Button(action: requestCameraPermission) {
                    Text(String(localized: "onboarding_allow_camera", defaultValue: "カメラを許可する"))
                        .font(.headline)
                        .foregroundColor(Color(.systemBackground))
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(Color.primary)
                        .cornerRadius(10)
                }
                .accessibilityLabel(Text("onboarding_allow_camera"))
            }
            Spacer()
            Spacer()
        }
        .onAppear {
            cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        }
    }

    // MARK: - Page 3: How to Use

    private var howToUsePage: some View {
        VStack(spacing: 32) {
            Spacer()
            Text(String(localized: "onboarding_howto_title", defaultValue: "使い方"))
                .font(.title2)
                .bold()
                .foregroundColor(.primary)
            VStack(alignment: .leading, spacing: 20) {
                howToStep(
                    icon: "camera.viewfinder",
                    title: String(localized: "onboarding_step1_title", defaultValue: "撮影する"),
                    description: String(localized: "onboarding_step1_desc", defaultValue: "古典籍のページをカメラで撮影")
                )
                howToStep(
                    icon: "text.viewfinder",
                    title: String(localized: "onboarding_step2_title", defaultValue: "認識する"),
                    description: String(localized: "onboarding_step2_desc", defaultValue: "AIが自動でくずし字を認識")
                )
                howToStep(
                    icon: "doc.on.doc",
                    title: String(localized: "onboarding_step3_title", defaultValue: "コピーする"),
                    description: String(localized: "onboarding_step3_desc", defaultValue: "認識結果をテキストとしてコピー")
                )
            }
            .padding(.horizontal, 40)
            Spacer()
            Spacer()
        }
    }

    private func howToStep(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(.blue)
                .frame(width: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Actions

    private func requestCameraPermission() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
            }
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
