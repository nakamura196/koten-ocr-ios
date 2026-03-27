import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

actor TranslationService {
    static let shared = TranslationService()

    private let apiKeyKeychainKey = "openai_api_key"
    private let endpointKey = "translation_api_endpoint"
    private let modelKey = "translation_api_model"
    private let levelKey = "translation_level"
    private let targetLanguageKey = "translation_target_language"
    private let maxTextLength = 5000

    static let defaultEndpoint = "https://openrouter.ai/api/v1/chat/completions"
    static let defaultModel = "openai/gpt-4o-mini"

    private let providerKey = "translation_api_provider"

    enum APIProvider: String, CaseIterable {
        case localAI = "localai"
        case openrouter = "openrouter"
        case openai = "openai"
        case custom = "custom"

        var displayName: String {
            switch self {
            case .localAI: return String(localized: "provider_local_ai", defaultValue: "ローカルAI（Apple）")
            case .openrouter: return "OpenRouter"
            case .openai: return "OpenAI"
            case .custom: return String(localized: "provider_custom", defaultValue: "カスタム")
            }
        }

        var endpoint: String {
            switch self {
            case .localAI: return ""
            case .openrouter: return "https://openrouter.ai/api/v1/chat/completions"
            case .openai: return "https://api.openai.com/v1/chat/completions"
            case .custom: return ""
            }
        }

        var defaultModel: String {
            switch self {
            case .localAI: return ""
            case .openrouter: return "openai/gpt-4o-mini"
            case .openai: return "gpt-4o-mini"
            case .custom: return ""
            }
        }

        var requiresAPIKey: Bool {
            switch self {
            case .localAI: return false
            case .openrouter, .openai, .custom: return true
            }
        }
    }

    func saveProvider(_ provider: APIProvider) {
        UserDefaults.standard.set(provider.rawValue, forKey: providerKey)
    }

    func loadProvider() -> APIProvider {
        guard let raw = UserDefaults.standard.string(forKey: providerKey) else { return .localAI }
        return APIProvider(rawValue: raw) ?? .localAI
    }

    enum TargetLanguage: String, CaseIterable {
        case japanese = "ja"
        case english = "en"

        var displayName: String {
            switch self {
            case .japanese: return String(localized: "target_lang_ja", defaultValue: "日本語（現代語）")
            case .english: return String(localized: "target_lang_en", defaultValue: "English")
            }
        }
    }

    enum TranslationLevel: String, CaseIterable {
        case general = "general"
        case student = "student"
        case researcher = "researcher"

        var displayName: String {
            switch self {
            case .general: return String(localized: "level_general", defaultValue: "一般向け")
            case .student: return String(localized: "level_student", defaultValue: "学生向け")
            case .researcher: return String(localized: "level_researcher", defaultValue: "研究者向け")
            }
        }

        var description: String {
            switch self {
            case .general: return String(localized: "level_general_desc", defaultValue: "わかりやすい現代語訳と簡単な解説")
            case .student: return String(localized: "level_student_desc", defaultValue: "正確な訳と語注・文法解説")
            case .researcher: return String(localized: "level_researcher_desc", defaultValue: "原文に忠実な直訳と詳細な注釈")
            }
        }

        func systemPrompt(for language: TargetLanguage) -> String {
            switch language {
            case .japanese:
                return japanesePrompt
            case .english:
                return englishPrompt
            }
        }

        private var japanesePrompt: String {
            switch self {
            case .general:
                return """
                あなたは古典日本語の専門家です。与えられた古文を現代日本語に翻訳してください。
                以下の形式で出力してください：

                【現代語訳】
                自然で読みやすい現代語訳を書いてください。

                【解説】
                この文章がどのような作品・資料のものか（わかる場合）、時代背景や内容の簡単な説明を2〜3文で書いてください。
                """
            case .student:
                return """
                あなたは古典日本語の専門家です。与えられた古文を学習者向けに詳しく翻訳・解説してください。
                以下の形式で出力してください：

                【現代語訳】
                原文に忠実で正確な現代語訳を書いてください。

                【語注】
                重要な古語・文法事項を箇条書きで説明してください（例：「あけぼの」＝夜明け）。

                【解説】
                作品名（わかる場合）、時代、ジャンル、文学的特徴などを説明してください。
                """
            case .researcher:
                return """
                あなたは古典日本語・古典文学の研究者です。与えられた古文を学術的に正確に分析してください。
                以下の形式で出力してください：

                【直訳】
                原文の構造に忠実な逐語的翻訳を書いてください。

                【語釈】
                重要な語句について、語義・用法・文法的説明を箇条書きで記してください。

                【解題】
                作品・資料の同定（可能な場合）、成立時期、ジャンル、書誌的情報、文学史的・歴史的位置づけについて記してください。
                """
            }
        }

        private var englishPrompt: String {
            switch self {
            case .general:
                return """
                You are an expert in classical Japanese literature. Translate the given classical Japanese (kobun/kuzushiji) text into modern English.
                Use the following format:

                [Translation]
                Provide a natural, readable English translation.

                [Commentary]
                Briefly describe what kind of text/work this is (if identifiable), its historical period, and context in 2-3 sentences.
                """
            case .student:
                return """
                You are an expert in classical Japanese literature. Translate and annotate the given classical Japanese text for learners.
                Use the following format:

                [Translation]
                Provide an accurate English translation faithful to the original.

                [Vocabulary]
                List important classical Japanese terms with their readings and meanings (e.g., あけぼの (akebono) = dawn).

                [Commentary]
                Explain the work (if identifiable), its period, genre, and literary significance.
                """
            case .researcher:
                return """
                You are a scholar of classical Japanese language and literature. Provide an academic analysis of the given classical Japanese text.
                Use the following format:

                [Literal Translation]
                Provide a word-by-word translation preserving the original syntactic structure.

                [Glossary]
                For key terms, provide: reading, meaning, grammatical analysis, and usage notes.

                [Bibliographic Note]
                Identify the work (if possible), its date of composition, genre, bibliographic details, and place in literary/historical context.
                """
            }
        }
    }

    enum TranslationError: LocalizedError {
        case noAPIKey
        case textTooLong
        case networkError(String)
        case serverError(Int, String)
        case invalidResponse
        case localAIUnavailable

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return String(localized: "translation_error_no_key", defaultValue: "APIキーが設定されていません")
            case .textTooLong:
                return String(localized: "translation_error_too_long", defaultValue: "テキストが長すぎます")
            case .networkError(let message):
                return message
            case .serverError(let code, let message):
                return "API Error (\(code)): \(message)"
            case .invalidResponse:
                return String(localized: "translation_error_invalid", defaultValue: "応答の解析に失敗しました")
            case .localAIUnavailable:
                return String(localized: "translation_error_local_ai", defaultValue: "ローカルAIはこのデバイスでは利用できません。iOS 26以降の対応デバイスが必要です。")
            }
        }
    }

    struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String
            }
            let message: Message
        }
        let choices: [Choice]
    }

    struct APIError: Decodable {
        struct ErrorDetail: Decodable {
            let message: String
        }
        let error: ErrorDetail
    }

    // MARK: - Settings

    var hasAPIKey: Bool {
        guard let key = KeychainHelper.load(key: apiKeyKeychainKey) else { return false }
        return !key.isEmpty
    }

    func saveAPIKey(_ key: String) {
        if key.isEmpty {
            KeychainHelper.delete(key: apiKeyKeychainKey)
        } else {
            KeychainHelper.save(key: apiKeyKeychainKey, value: key)
        }
    }

    func loadAPIKey() -> String {
        KeychainHelper.load(key: apiKeyKeychainKey) ?? ""
    }

    func saveEndpoint(_ endpoint: String) {
        UserDefaults.standard.set(endpoint, forKey: endpointKey)
    }

    func loadEndpoint() -> String {
        UserDefaults.standard.string(forKey: endpointKey) ?? Self.defaultEndpoint
    }

    func saveModel(_ model: String) {
        UserDefaults.standard.set(model, forKey: modelKey)
    }

    func loadModel() -> String {
        UserDefaults.standard.string(forKey: modelKey) ?? Self.defaultModel
    }

    func saveLevel(_ level: TranslationLevel) {
        UserDefaults.standard.set(level.rawValue, forKey: levelKey)
    }

    func loadLevel() -> TranslationLevel {
        guard let raw = UserDefaults.standard.string(forKey: levelKey) else { return .general }
        return TranslationLevel(rawValue: raw) ?? .general
    }

    func saveTargetLanguage(_ lang: TargetLanguage) {
        UserDefaults.standard.set(lang.rawValue, forKey: targetLanguageKey)
    }

    func loadTargetLanguage() -> TargetLanguage {
        guard let raw = UserDefaults.standard.string(forKey: targetLanguageKey) else { return .japanese }
        return TargetLanguage(rawValue: raw) ?? .japanese
    }

    // MARK: - Local AI Availability

    enum LocalAIStatus {
        case available
        case intelligenceNotEnabled
        case modelNotReady
        case deviceNotEligible
        case osNotSupported

        var message: String {
            switch self {
            case .available:
                return String(localized: "local_ai_ready", defaultValue: "オンデバイスAIが利用可能です")
            case .intelligenceNotEnabled:
                return String(localized: "local_ai_not_enabled", defaultValue: "Apple Intelligenceが有効になっていません。「設定  > Apple Intelligence と Siri」で有効にしてください。")
            case .modelNotReady:
                return String(localized: "local_ai_model_not_ready", defaultValue: "AIモデルをダウンロード中です。Wi-Fi接続の上、しばらくお待ちください。")
            case .deviceNotEligible:
                return String(localized: "local_ai_device_not_eligible", defaultValue: "このデバイスはローカルAIに対応していません。iPhone 15 Pro以降が必要です。")
            case .osNotSupported:
                return String(localized: "local_ai_os_not_supported", defaultValue: "ローカルAIにはiOS 26以降が必要です。")
            }
        }
    }

    var localAIStatus: LocalAIStatus {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            let availability = SystemLanguageModel.default.availability
            switch availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .appleIntelligenceNotEnabled:
                    return .intelligenceNotEnabled
                case .modelNotReady:
                    return .modelNotReady
                case .deviceNotEligible:
                    return .deviceNotEligible
                @unknown default:
                    return .deviceNotEligible
                }
            @unknown default:
                return .deviceNotEligible
            }
        }
        #endif
        return .osNotSupported
    }

    var isLocalAIAvailable: Bool {
        return localAIStatus == .available
    }

    // MARK: - Translation

    func translate(text: String) async throws -> String {
        let provider = loadProvider()

        if provider == .localAI {
            return try await translateWithLocalAIFallback(text: text)
        }

        return try await translateWithAPI(text: text)
    }

    #if canImport(FoundationModels)
    @available(iOS 26, *)
    private func translateWithLocalAI(text: String) async throws -> String {
        let model = SystemLanguageModel.default
        guard model.availability == .available else {
            throw TranslationError.localAIUnavailable
        }

        guard text.count <= maxTextLength else {
            throw TranslationError.textTooLong
        }

        let level = loadLevel()
        let targetLang = loadTargetLanguage()
        let systemPrompt = level.systemPrompt(for: targetLang)

        let session = LanguageModelSession(instructions: systemPrompt)
        let response = try await session.respond(to: text)
        return response.content
    }
    #endif

    private func translateWithLocalAIFallback(text: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            return try await translateWithLocalAI(text: text)
        }
        #endif
        throw TranslationError.localAIUnavailable
    }

    private func translateWithAPI(text: String) async throws -> String {
        guard let apiKey = KeychainHelper.load(key: apiKeyKeychainKey), !apiKey.isEmpty else {
            throw TranslationError.noAPIKey
        }

        guard text.count <= maxTextLength else {
            throw TranslationError.textTooLong
        }

        let endpoint = loadEndpoint()
        let model = loadModel()

        guard let url = URL(string: endpoint) else {
            throw TranslationError.networkError("Invalid endpoint URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        let level = loadLevel()
        let targetLang = loadTargetLanguage()

        let body: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "system",
                    "content": level.systemPrompt(for: targetLang)
                ],
                [
                    "role": "user",
                    "content": text
                ]
            ],
            "temperature": 0.3,
            "max_tokens": 2000
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            if let apiError = try? JSONDecoder().decode(APIError.self, from: data) {
                throw TranslationError.serverError(httpResponse.statusCode, apiError.error.message)
            }
            throw TranslationError.serverError(httpResponse.statusCode, "Unknown error")
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw TranslationError.invalidResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
