import SwiftUI
import AVFoundation

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentPage = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

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
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
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
                .foregroundColor(.white)
            Text(String(localized: "onboarding_intro", defaultValue: "古典籍・くずし字の文字認識アプリ。\nカメラで撮影するだけで、くずし字をテキストに変換します。"))
                .font(.body)
                .foregroundColor(.gray)
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
            Image(systemName: "camera.fill")
                .font(.system(size: 60))
                .foregroundColor(.white)
            Text(String(localized: "onboarding_camera_title", defaultValue: "カメラへのアクセス"))
                .font(.title2)
                .bold()
                .foregroundColor(.white)
            Text(String(localized: "onboarding_camera_description", defaultValue: "古典籍の文字を認識するために、\nカメラへのアクセスを許可してください。"))
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button(action: requestCameraPermission) {
                Text(String(localized: "onboarding_allow_camera", defaultValue: "カメラを許可する"))
                    .font(.headline)
                    .foregroundColor(.black)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .cornerRadius(10)
            }
            Spacer()
            Spacer()
        }
    }

    // MARK: - Page 3: How to Use

    private var howToUsePage: some View {
        VStack(spacing: 32) {
            Spacer()
            Text(String(localized: "onboarding_howto_title", defaultValue: "使い方"))
                .font(.title2)
                .bold()
                .foregroundColor(.white)
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
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
        }
    }

    // MARK: - Actions

    private func requestCameraPermission() {
        AVCaptureDevice.requestAccess(for: .video) { _ in }
    }
}
