import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationView {
            List {
                aboutSection
                licenseSection
                linkSection
            }
            .navigationTitle(String(localized: "settings_title", defaultValue: "設定"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
            }
        }
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
            Link(destination: URL(string: "https://github.com/ndl-lab/ndlkotenocr-lite")!) {
                HStack {
                    Text("NDL Lab GitHub")
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .foregroundColor(.secondary)
                }
            }
        }
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
                Link("https://github.com/ndl-lab/ndlkotenocr-lite",
                     destination: URL(string: "https://github.com/ndl-lab/ndlkotenocr-lite")!)
                    .font(.subheadline)
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
                Link("https://github.com/microsoft/onnxruntime",
                     destination: URL(string: "https://github.com/microsoft/onnxruntime")!)
                    .font(.subheadline)
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
