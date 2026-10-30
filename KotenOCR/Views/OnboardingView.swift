import SwiftUI
import AVFoundation

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentPage = 0
    @State private var cameraStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var introFinished = false

    var body: some View {
        ZStack {
            WashiBackground()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    introPage.tag(0)
                    cameraPermissionPage.tag(1)
                    howToUsePage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                Button(action: {
                    if currentPage < 2 {
                        withAnimation { currentPage += 1 }
                    } else {
                        hasCompletedOnboarding = true
                    }
                }) {
                    Text(currentPage < 2
                         ? String(localized: "onboarding_next", defaultValue: "次へ")
                         : String(localized: "onboarding_start", defaultValue: "はじめる"))
                        .font(.title3.weight(.heavy))
                        .frame(maxWidth: .infinity, minHeight: 58)
                }
                .buttonStyle(.kotenProminent)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .opacity(currentPage > 0 || introFinished ? 1 : 0)
                .accessibilityIdentifier(currentPage < 2 ? "onboarding_next_button" : "onboarding_start_button")
            }
        }
        .tint(KotenColor.shu)
    }

    // MARK: - Page 1: Intro (animated, about 3 s)

    private var introPage: some View {
        ScrollView {
            VStack(spacing: 0) {
                OnboardingIntroAnimation(finished: $introFinished)
                    .padding(.top, 40)
                VStack(spacing: 14) {
                    Text("onboarding_heading")
                        .font(.mincho(30, relativeTo: .largeTitle, bold: true))
                        .foregroundColor(KotenColor.ink)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text(String(localized: "onboarding_intro", defaultValue: "古典籍・くずし字の文字認識アプリ。\nカメラで撮影するだけで、くずし字をテキストに変換します。"))
                        .font(.body)
                        .foregroundColor(KotenColor.inkSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 28)
                .padding(.top, 26)
                .padding(.bottom, 48)
                .opacity(introFinished ? 1 : 0)
                .offset(y: introFinished ? 0 : 12)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Page 2: Camera Permission

    private var cameraPermissionPage: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: cameraStatus == .authorized ? "checkmark.circle.fill" : "camera.fill")
                .font(.system(size: 60))
                .foregroundColor(KotenColor.shu)
                .accessibilityHidden(true)
            Text(String(localized: "onboarding_camera_title", defaultValue: "カメラへのアクセス"))
                .font(.mincho(26, relativeTo: .title2, bold: true))
                .foregroundColor(KotenColor.ink)
            Text(String(localized: "onboarding_camera_description", defaultValue: "古典籍の文字を認識するために、\nカメラへのアクセスを許可してください。"))
                .font(.body)
                .foregroundColor(KotenColor.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            switch cameraStatus {
            case .authorized:
                Text(String(localized: "onboarding_camera_granted", defaultValue: "カメラは許可済みです"))
                    .font(.subheadline)
                    .foregroundColor(KotenColor.shu)
            case .denied, .restricted:
                VStack(spacing: 12) {
                    Text(String(localized: "onboarding_camera_denied", defaultValue: "カメラが許可されていません"))
                        .font(.subheadline)
                        .foregroundColor(KotenColor.shu)
                    Button(action: openSettings) {
                        Text(String(localized: "camera_open_settings", defaultValue: "設定を開く"))
                            .font(.headline)
                                                        .padding(.horizontal, 32)
                            .frame(minHeight: 50)
                    }
                    .buttonStyle(.kotenGlass)
                    .accessibilityLabel(Text("camera_open_settings"))
                }
            default:
                Button(action: requestCameraPermission) {
                    Text(String(localized: "onboarding_allow_camera", defaultValue: "カメラを許可する"))
                        .font(.headline)
                                                .padding(.horizontal, 32)
                        .frame(minHeight: 50)
                }
                .buttonStyle(.kotenGlass)
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
                .font(.mincho(26, relativeTo: .title2, bold: true))
                .foregroundColor(KotenColor.ink)
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
                .font(.system(size: 28, weight: .light))
                .foregroundColor(KotenColor.shu)
                .frame(width: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.mincho(18, relativeTo: .headline, bold: true))
                    .foregroundColor(KotenColor.ink)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(KotenColor.inkSecondary)
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

/// First-run animation (guidance 1): a sample manuscript page appears, a 朱 frame is drawn
/// around it, then the read text rises along the lines. Ends after about 3 s.
/// With Reduce Motion the final state fades in at once.
private struct OnboardingIntroAnimation: View {
    @Binding var finished: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage = 0
    @State private var frameProgress: CGFloat = 0

    /// Opening phrases of the Kiritsubo chapter, as on the sample page.
    private let columns = ["いつれの御時にか", "女御更衣あまた", "さふらひ給ける中に"]

    var body: some View {
        GeometryReader { geo in
            let w = min(geo.size.width, 300)
            let s = w / 300
            ZStack(alignment: .topTrailing) {
                Image("OnboardingSample")
                    .resizable()
                    .scaledToFill()
                    .frame(width: w, height: w * 380 / 300)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: Color(red: 0.31, green: 0.24, blue: 0.12).opacity(0.25), radius: 15, y: 10)

                RoundedRectangle(cornerRadius: 6)
                    .trim(from: 0, to: frameProgress)
                    .stroke(KotenColor.shu, style: StrokeStyle(lineWidth: 7 * s, lineCap: .round))
                    .padding(3 * s)
                    .frame(width: w, height: w * 380 / 300)

                ForEach(Array(columns.enumerated()), id: \.offset) { i, text in
                    VStack(spacing: 2 * s) {
                        ForEach(Array(text.enumerated()), id: \.offset) { _, ch in
                            Text(String(ch))
                                .font(.custom("HiraMinProN-W6", fixedSize: 24 * s))
                        }
                    }
                    .foregroundColor(Color(red: 0.169, green: 0.149, blue: 0.133))
                    .padding(.vertical, 8 * s)
                    .padding(.horizontal, 5 * s)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.98, green: 0.957, blue: 0.91).opacity(0.92)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(KotenColor.shu, lineWidth: 2))
                    .offset(x: -(18 + CGFloat(i) * 52) * s, y: 40 * s + (stage >= 3 + i ? 0 : 30 * s))
                    .opacity(stage >= 3 + i ? 1 : 0)
                }
            }
            .frame(width: w, height: w * 380 / 300)
            .opacity(stage >= 1 ? 1 : 0)
            .offset(y: stage >= 1 || reduceMotion ? 0 : 16)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 380)
        .padding(.horizontal, 45)
        .accessibilityHidden(true)
        .onAppear(perform: play)
    }

    private func play() {
        guard stage == 0 else { return }
        if reduceMotion {
            frameProgress = 1
            withAnimation(.easeOut(duration: 0.3)) { stage = 5 }
            finished = true
            return
        }
        // 0–600 ms: the page appears.
        withAnimation(.easeOut(duration: 0.6)) { stage = 1 }
        // 600–1400 ms: the 朱 frame is drawn.
        after(0.6) { withAnimation(.easeInOut(duration: 0.8)) { frameProgress = 1 } }
        // 1400–2400 ms: the read text rises, one column after another.
        after(1.4) { withAnimation(.easeOut(duration: 0.45)) { stage = 3 } }
        after(1.7) { withAnimation(.easeOut(duration: 0.45)) { stage = 4 } }
        after(2.0) { withAnimation(.easeOut(duration: 0.45)) { stage = 5 } }
        // 2400–3000 ms: heading and "Next".
        after(2.4) { withAnimation(.easeOut(duration: 0.5)) { finished = true } }
    }

    private func after(_ seconds: Double, _ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: block)
    }
}
