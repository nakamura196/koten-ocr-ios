import SwiftUI
import AVFoundation

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue
    @AppStorage("appLanguage") private var appLanguage: String = "system"
    @AppStorage("saveToLibrary") private var saveToLibrary = false
    @State private var showRestartAlert = false
    @State private var cameraStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var appTheme: AppTheme {
        AppTheme(rawValue: appThemeRaw) ?? .system
    }

    var body: some View {
        NavigationView {
            List {
                aboutSection
                translationAPISection
                cameraSection
                themeSection
                languageSection
                tipJarSection
                feedbackSection
                licenseSection
                linkSection
            }
            .navigationTitle(String(localized: "settings_title", defaultValue: "設定"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel(Text("close"))
                }
            }
            .alert(String(localized: "language_restart_title", defaultValue: "Restart Required"), isPresented: $showRestartAlert) {
                Button(String(localized: "ok", defaultValue: "OK")) {}
            } message: {
                Text(String(localized: "language_restart_message", defaultValue: "Please restart the app to apply the language change."))
            }
        }
        .preferredColorScheme(appTheme.colorScheme)
    }

    // MARK: - About

    private var aboutSection: some View {
        Section(header: Text(String(localized: "settings_about", defaultValue: "About"))) {
            HStack {
                Image("AppIconDisplay")
                    .resizable()
                    .frame(width: 48, height: 48)
                    .cornerRadius(10)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("KotenOCR")
                        .font(.headline)
                    Text(String(localized: "settings_version", defaultValue: "バージョン") + " \(appVersion)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Translation

    private var translationAPISection: some View {
        Section(header: Text(String(localized: "settings_translation_api", defaultValue: "現代語訳"))) {
            NavigationLink {
                TranslationSettingsView()
            } label: {
                HStack {
                    Image(systemName: "text.book.closed")
                        .foregroundColor(.blue)
                    Text(String(localized: "settings_translation_nav", defaultValue: "現代語訳"))
                }
            }
        }
    }

    // MARK: - Camera

    private var cameraSection: some View {
        Section(header: Text(String(localized: "settings_camera", defaultValue: "Camera"))) {
            HStack {
                Text(String(localized: "settings_camera_permission", defaultValue: "カメラの許可"))
                Spacer()
                switch cameraStatus {
                case .authorized:
                    Text(String(localized: "camera_status_authorized", defaultValue: "許可済み"))
                        .foregroundColor(.green)
                case .denied, .restricted:
                    Button(action: openSettings) {
                        Text(String(localized: "camera_status_denied", defaultValue: "許可されていません"))
                            .foregroundColor(.red)
                    }
                case .notDetermined:
                    Text(String(localized: "camera_status_not_set", defaultValue: "未設定"))
                        .foregroundColor(.secondary)
                @unknown default:
                    EmptyView()
                }
            }
            .onAppear {
                cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
            }

            if cameraStatus == .denied || cameraStatus == .restricted {
                Button(action: openSettings) {
                    HStack {
                        Image(systemName: "gear")
                            .foregroundColor(.blue)
                        Text(String(localized: "camera_open_settings", defaultValue: "設定を開く"))
                            .foregroundColor(.blue)
                    }
                }
            }

            Toggle(String(localized: "settings_save_to_library", defaultValue: "Save to Photo Library"),
                   isOn: $saveToLibrary)
        }
    }

    // MARK: - Theme

    private var themeSection: some View {
        Section(header: Text(String(localized: "settings_theme", defaultValue: "Appearance"))) {
            Picker(String(localized: "settings_theme", defaultValue: "Appearance"), selection: $appThemeRaw) {
                ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                    Text(theme.displayName).tag(theme.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(Text("settings_theme"))
        }
    }

    // MARK: - Language

    private var languageSection: some View {
        Section(header: Text(String(localized: "settings_language", defaultValue: "Language"))) {
            Picker(String(localized: "settings_language", defaultValue: "Language"), selection: $appLanguage) {
                Text(String(localized: "language_system", defaultValue: "System")).tag("system")
                Text(String(localized: "language_ja", defaultValue: "Japanese")).tag("ja")
                Text(String(localized: "language_en", defaultValue: "English")).tag("en")
            }
            .onChange(of: appLanguage) { newValue in
                applyLanguage(newValue)
                showRestartAlert = true
            }
            .accessibilityLabel(Text("settings_language"))
        }
    }

    // MARK: - Tip Jar

    private var tipJarSection: some View {
        Section(header: Text(String(localized: "settings_tipjar", defaultValue: "Support Us"))) {
            NavigationLink {
                TipJarView()
            } label: {
                HStack {
                    Image(systemName: "heart.fill")
                        .foregroundColor(.pink)
                    Text(String(localized: "tipjar_nav_title", defaultValue: "Tip Jar"))
                }
            }
            .accessibilityLabel(Text("tipjar_nav_title"))
        }
    }

    // MARK: - Feedback

    private var feedbackSection: some View {
        Section(header: Text(String(localized: "settings_feedback", defaultValue: "フィードバック"))) {
            Button(action: sendFeedback) {
                HStack {
                    Image(systemName: "envelope")
                        .foregroundColor(.blue)
                    Text(String(localized: "settings_send_feedback", defaultValue: "フィードバックを送る"))
                }
            }
        }
    }

    private func sendFeedback() {
        let device = UIDevice.current
        let systemVersion = device.systemVersion
        let modelName = device.model
        let subject = "KotenOCR Feedback (v\(appVersion))"
        let body = """


        ---
        Device: \(modelName)
        iOS: \(systemVersion)
        App: \(appVersion)
        """
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "mailto:na.kamura.1263@gmail.com?subject=\(encodedSubject)&body=\(encodedBody)") {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Licenses

    private var licenseSection: some View {
        Section(header: Text(String(localized: "settings_licenses", defaultValue: "ライセンス"))) {
            NavigationLink {
                ndlLicenseDetail
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NDL古典籍OCR-Lite")
                        .font(.body)
                    Text("CC-BY-4.0 — 国立国会図書館")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            NavigationLink {
                ndlocrLiteLicenseDetail
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NDLOCR-Lite")
                        .font(.body)
                    Text("CC-BY-4.0 — 国立国会図書館")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            NavigationLink {
                onnxLicenseDetail
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ONNX Runtime")
                        .font(.body)
                    Text("MIT License — Microsoft")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Links

    private var linkSection: some View {
        Section(header: Text(String(localized: "settings_links", defaultValue: "リンク"))) {
            if let url = URL(string: "https://github.com/ndl-lab/ndlkotenocr-lite") {
                Link(destination: url) {
                    HStack {
                        Text("NDL Lab GitHub")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Camera Permission

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Language

    private func applyLanguage(_ language: String) {
        if language == "system" {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([language], forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()
    }

    // MARK: - License Details

    private var ndlLicenseDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("NDL古典籍OCR-Lite")
                    .font(.title2)
                    .bold()
                Text("© 国立国会図書館 (National Diet Library)")
                    .font(.subheadline)
                Text("Creative Commons Attribution 4.0 International (CC-BY-4.0)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                if let repoURL = URL(string: "https://github.com/ndl-lab/ndlkotenocr-lite") {
                    Link("https://github.com/ndl-lab/ndlkotenocr-lite", destination: repoURL)
                        .font(.subheadline)
                }
                Divider()
                Text(ccby4FullText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .navigationTitle("NDL古典籍OCR-Lite")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var ndlocrLiteLicenseDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("NDLOCR-Lite")
                    .font(.title2)
                    .bold()
                Text("© 国立国会図書館 (National Diet Library)")
                    .font(.subheadline)
                Text("Creative Commons Attribution 4.0 International (CC-BY-4.0)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                if let repoURL = URL(string: "https://github.com/ndl-lab/ndlocr-lite") {
                    Link("https://github.com/ndl-lab/ndlocr-lite", destination: repoURL)
                        .font(.subheadline)
                }
                Divider()
                Text(ccby4FullText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .navigationTitle("NDLOCR-Lite")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var onnxLicenseDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("ONNX Runtime")
                    .font(.title2)
                    .bold()
                Text("© Microsoft Corporation")
                    .font(.subheadline)
                Text("MIT License")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                if let repoURL = URL(string: "https://github.com/microsoft/onnxruntime") {
                    Link("https://github.com/microsoft/onnxruntime", destination: repoURL)
                        .font(.subheadline)
                }
                Divider()
                Text(mitFullText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .navigationTitle("ONNX Runtime")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - License Texts

    private var ccby4FullText: String {
        """
        Creative Commons Attribution 4.0 International Public License

        By exercising the Licensed Rights (defined below), You accept and agree to be bound by the terms and conditions of this Creative Commons Attribution 4.0 International Public License ("Public License"). To the extent this Public License may be interpreted as a contract, You are granted the Licensed Rights in consideration of Your acceptance of these terms and conditions, and the Licensor grants You such rights in consideration of benefits the Licensor receives from making the Licensed Material available under these terms and conditions.

        Section 1 – Definitions.
        a. Adapted Material means material subject to Copyright and Similar Rights that is derived from or based upon the Licensed Material and in which the Licensed Material is translated, altered, arranged, transformed, or otherwise modified in a manner requiring permission under the Copyright and Similar Rights held by the Licensor.
        b. Copyright and Similar Rights means copyright and/or similar rights closely related to copyright.
        c. Licensed Material means the artistic or literary work, database, or other material to which the Licensor applied this Public License.
        d. Licensed Rights means the rights granted to You subject to the terms and conditions of this Public License.
        e. Licensor means the individual(s) or entity(ies) granting rights under this Public License.
        f. Share means to provide material to the public by any means or process.
        g. You means the individual or entity exercising the Licensed Rights under this Public License.

        Section 2 – Scope.
        a. License grant. Subject to the terms and conditions of this Public License, the Licensor hereby grants You a worldwide, royalty-free, non-sublicensable, non-exclusive, irrevocable license to reproduce and Share the Licensed Material, in whole or in part; and produce, reproduce, and Share Adapted Material.
        b. The Licensor shall not be bound by any additional or different terms or conditions communicated by You unless expressly agreed.

        Section 3 – License Conditions.
        Attribution. If You Share the Licensed Material, You must retain identification of the creator(s), a copyright notice, a notice that refers to this Public License, a notice that refers to the disclaimer of warranties, and a URI or hyperlink to the Licensed Material.

        Section 4 – Disclaimer of Warranties and Limitation of Liability.
        The Licensed Material is provided "as-is" and "as-available", and the Licensor makes no representations or warranties of any kind concerning the Licensed Material.

        For the full license text, visit:
        https://creativecommons.org/licenses/by/4.0/legalcode
        """
    }

    private var mitFullText: String {
        """
        MIT License

        Copyright (c) Microsoft Corporation

        Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
        """
    }
}
