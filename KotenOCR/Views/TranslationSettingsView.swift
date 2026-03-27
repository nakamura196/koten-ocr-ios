import SwiftUI

struct TranslationSettingsView: View {
    @State private var apiKey: String = ""
    @State private var apiEndpoint: String = ""
    @State private var apiModel: String = ""
    @State private var selectedProvider: TranslationService.APIProvider = .localAI
    @State private var translationLevel: TranslationService.TranslationLevel = .general
    @State private var targetLanguage: TranslationService.TargetLanguage = .japanese
    @State private var showSaved = false
    @State private var localAIAvailable = false
    @State private var localAIStatus: TranslationService.LocalAIStatus = .osNotSupported

    private var isCustomProvider: Bool {
        selectedProvider == .custom
    }

    private var isLocalAIProvider: Bool {
        selectedProvider == .localAI
    }

    /// Providers to show in the picker — exclude `.localAI` on iOS < 26
    private var availableProviders: [TranslationService.APIProvider] {
        TranslationService.APIProvider.allCases.filter { provider in
            if provider == .localAI {
                if #available(iOS 26, *) { return true }
                return false
            }
            return true
        }
    }

    var body: some View {
        List {
            // Translation options (simple, shown first)
            Section(header: Text(String(localized: "settings_translation_options", defaultValue: "翻訳オプション"))) {
                Picker(String(localized: "settings_target_language", defaultValue: "翻訳先言語"), selection: $targetLanguage) {
                    ForEach(TranslationService.TargetLanguage.allCases, id: \.rawValue) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .onChange(of: targetLanguage) { newValue in
                    Task { await TranslationService.shared.saveTargetLanguage(newValue) }
                }

                Picker(String(localized: "settings_translation_level", defaultValue: "解説レベル"), selection: $translationLevel) {
                    ForEach(TranslationService.TranslationLevel.allCases, id: \.rawValue) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .onChange(of: translationLevel) { newValue in
                    Task { await TranslationService.shared.saveLevel(newValue) }
                }

                Text(translationLevel.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Provider selection
            Section(header: Text(String(localized: "settings_provider", defaultValue: "翻訳プロバイダー"))) {
                Picker(String(localized: "settings_api_provider", defaultValue: "プロバイダー"), selection: $selectedProvider) {
                    ForEach(availableProviders, id: \.rawValue) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .onChange(of: selectedProvider) { newValue in
                    if newValue != .custom && newValue != .localAI {
                        apiEndpoint = newValue.endpoint
                        apiModel = newValue.defaultModel
                    }
                    Task { await TranslationService.shared.saveProvider(newValue) }
                }

                if isLocalAIProvider {
                    switch localAIStatus {
                    case .available:
                        Label(localAIStatus.message, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    case .modelNotReady:
                        Label(localAIStatus.message, systemImage: "arrow.down.circle")
                            .font(.caption)
                            .foregroundColor(.blue)
                    case .intelligenceNotEnabled:
                        Label(localAIStatus.message, systemImage: "gearshape")
                            .font(.caption)
                            .foregroundColor(.orange)
                    default:
                        Label(localAIStatus.message, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }

            // API settings — only shown for cloud providers
            if !isLocalAIProvider {
                Section(header: Text(String(localized: "settings_api_config", defaultValue: "API設定")),
                        footer: Text(String(localized: "settings_api_footer", defaultValue: "OpenAI互換APIに対応（OpenAI、OpenRouter等）。APIキーはKeychainに安全に保存されます。"))) {

                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "settings_api_key", defaultValue: "APIキー"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        SecureField("sk-...", text: $apiKey)
                            .textContentType(.password)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .font(.system(.body, design: .monospaced))
                    }
                    .padding(.vertical, 2)

                    if isCustomProvider {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "settings_api_endpoint", defaultValue: "エンドポイント"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("https://api.example.com/v1/chat/completions", text: $apiEndpoint)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .keyboardType(.URL)
                                .font(.system(.body, design: .monospaced))
                        }
                        .padding(.vertical, 2)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "settings_api_model", defaultValue: "モデル"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("gpt-4o-mini", text: $apiModel)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .font(.system(.body, design: .monospaced))
                        }
                        .padding(.vertical, 2)
                    } else {
                        HStack {
                            Text(String(localized: "settings_api_endpoint", defaultValue: "エンドポイント"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(apiEndpoint)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        HStack {
                            Text(String(localized: "settings_api_model", defaultValue: "モデル"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(apiModel)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    Button {
                        Task {
                            let service = TranslationService.shared
                            await service.saveAPIKey(apiKey)
                            let endpoint = apiEndpoint.isEmpty ? selectedProvider.endpoint : apiEndpoint
                            let model = apiModel.isEmpty ? selectedProvider.defaultModel : apiModel
                            await service.saveEndpoint(endpoint)
                            await service.saveModel(model)
                            showSaved = true
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Text(String(localized: "settings_api_save", defaultValue: "保存"))
                                .bold()
                            Spacer()
                        }
                    }
                    .tint(.blue)
                }
            }
        }
        .navigationTitle(String(localized: "settings_translation_nav", defaultValue: "現代語訳"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(String(localized: "api_key_saved_title", defaultValue: "保存しました"), isPresented: $showSaved) {
            Button(String(localized: "ok", defaultValue: "OK")) {}
        }
        .task {
            let service = TranslationService.shared
            apiKey = await service.loadAPIKey()
            apiEndpoint = await service.loadEndpoint()
            apiModel = await service.loadModel()
            selectedProvider = await service.loadProvider()
            translationLevel = await service.loadLevel()
            targetLanguage = await service.loadTargetLanguage()
            localAIAvailable = await service.isLocalAIAvailable
            localAIStatus = await service.localAIStatus
        }
    }
}
