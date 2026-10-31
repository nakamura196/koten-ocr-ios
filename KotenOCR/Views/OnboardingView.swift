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
                    .padding(.top, 12)
                VStack(spacing: 14) {
                    Text("onboarding_heading")
                        .font(.mincho(30, relativeTo: .largeTitle, bold: true))
                        .foregroundColor(KotenColor.ink)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text(String(localized: "onboarding_intro", defaultValue: "古典籍・くずし字の文字認識アプリ。\nカメラで撮影するか、写真を選ぶだけで、くずし字をテキストに変換します。"))
                        .font(.body)
                        .foregroundColor(KotenColor.inkSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 28)
                .padding(.top, 20)
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
                    description: String(localized: "onboarding_step1_desc", defaultValue: "古典籍のページをカメラで撮影（パソコンなどから「写真」に入れた画像も選べます）")
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

/// First-run animation (guidance 1). Replays a real recognition result of the sample page
/// (KotenOCR/Resources/onboarding_sample_ocr.json, made by OnboardingSampleGenerator) with the
/// same look and timing as the reading screen: the grey page, the 朱 beam, then the boxes in
/// reading order (right to left), then the first recognized lines. About 3 s; no OCR runs here.
/// With Reduce Motion the final state is shown as a still image.
private struct OnboardingIntroAnimation: View {
    @Binding var finished: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var sweep: CGFloat = 0
    @State private var revealed = 0
    @State private var showLines = false

    private let sample = OnboardingSample.load()
    private let image = UIImage(named: "OnboardingSample")
    private var boxes: [CGRect] {
        (sample?.lines ?? []).map { l in
            CGRect(x: l.box[0], y: l.box[1], width: l.box[2] - l.box[0], height: l.box[3] - l.box[1])
        }
    }
    private var scanned: Bool { revealed > 0 }

    var body: some View {
        VStack(spacing: 14) {
            if let image {
                ZStack {
                    // Not yet read: grey and slightly sepia, as on the reading screen.
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .grayscale(1)
                        .colorMultiply(Color(red: 0.95, green: 0.9, blue: 0.82))
                        .brightness(-0.05)
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .mask(alignment: .trailing) {
                            GeometryReader { geo in
                                Rectangle()
                                    .frame(width: geo.size.width * (scanned ? 1 : sweep))
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        }
                        .overlay {
                            GeometryReader { geo in
                                ZStack(alignment: .topLeading) {
                                    if !scanned && sweep > 0 && sweep < 1 {
                                        ScanBeam(height: geo.size.height)
                                            .position(x: geo.size.width * (1 - sweep), y: geo.size.height / 2)
                                    }
                                    RevealedBoxes(boxes: boxes, revealed: revealed, size: geo.size)
                                }
                            }
                        }
                }
                .kotenMount()
                .frame(maxHeight: 330)
                // Required by the library's reuse terms (cropped and overlaid = modified).
                Text("onboarding_sample_credit")
                    .font(.caption2)
                    .foregroundColor(KotenColor.inkSecondary)
                    .multilineTextAlignment(.center)
            }

            if showLines, let lines = sample?.lines.prefix(3) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(KotenColor.shu)
                            Text(line.text)
                                .font(.mincho(16, relativeTo: .body))
                                .foregroundColor(KotenColor.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(KotenColor.washiCard))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(KotenColor.rule, lineWidth: 1))
                .transition(.opacity)
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : 16)
        .padding(.horizontal, 32)
        .accessibilityHidden(true)
        .onAppear(perform: play)
    }

    private func play() {
        guard !appeared else { return }
        let count = boxes.count
        if reduceMotion || count == 0 {
            appeared = true
            sweep = 1
            revealed = count
            showLines = count > 0
            finished = true
            return
        }
        // 0–500 ms: the page appears, grey.
        withAnimation(.easeOut(duration: 0.5)) { appeared = true }
        // 500–1300 ms: the 朱 beam sweeps right → left.
        after(0.5) { withAnimation(.linear(duration: 0.8)) { sweep = 1 } }
        // 1300–2100 ms: the real boxes appear one by one in reading order (as on the reading screen).
        let step = min(0.08, 0.8 / Double(count))
        for i in 1...count {
            after(1.3 + step * Double(i)) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { revealed = i }
            }
        }
        // 2100–2600 ms: the first recognized lines, then heading and "Next".
        after(2.15) { withAnimation(.easeOut(duration: 0.35)) { showLines = true } }
        after(2.5) { withAnimation(.easeOut(duration: 0.45)) { finished = true } }
    }

    private func after(_ seconds: Double, _ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: block)
    }
}
