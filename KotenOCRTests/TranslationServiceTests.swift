import XCTest
@testable import KotenOCR

final class TranslationServiceTests: XCTestCase {

    // MARK: - ChatResponse Decoding

    func testDecodeChatResponse() throws {
        let json = """
        {
            "choices": [
                {
                    "message": {
                        "content": "翻訳結果です。"
                    }
                }
            ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(TranslationService.ChatResponse.self, from: json)
        XCTAssertEqual(response.choices.count, 1)
        XCTAssertEqual(response.choices[0].message.content, "翻訳結果です。")
    }

    func testDecodeChatResponseMultipleChoices() throws {
        let json = """
        {
            "choices": [
                {"message": {"content": "first"}},
                {"message": {"content": "second"}}
            ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(TranslationService.ChatResponse.self, from: json)
        XCTAssertEqual(response.choices.count, 2)
        XCTAssertEqual(response.choices[1].message.content, "second")
    }

    func testDecodeChatResponseEmptyChoices() throws {
        let json = """
        {"choices": []}
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(TranslationService.ChatResponse.self, from: json)
        XCTAssertTrue(response.choices.isEmpty)
    }

    // MARK: - APIError Decoding

    func testDecodeAPIError() throws {
        let json = """
        {
            "error": {
                "message": "Invalid API key"
            }
        }
        """.data(using: .utf8)!

        let error = try JSONDecoder().decode(TranslationService.APIError.self, from: json)
        XCTAssertEqual(error.error.message, "Invalid API key")
    }

    // MARK: - APIProvider

    func testAPIProviderEndpoints() {
        XCTAssertEqual(
            TranslationService.APIProvider.openrouter.endpoint,
            "https://openrouter.ai/api/v1/chat/completions"
        )
        XCTAssertEqual(
            TranslationService.APIProvider.openai.endpoint,
            "https://api.openai.com/v1/chat/completions"
        )
        XCTAssertEqual(TranslationService.APIProvider.custom.endpoint, "")
        XCTAssertEqual(TranslationService.APIProvider.localAI.endpoint, "")
    }

    func testAPIProviderDefaultModels() {
        XCTAssertEqual(TranslationService.APIProvider.openrouter.defaultModel, "openai/gpt-4o-mini")
        XCTAssertEqual(TranslationService.APIProvider.openai.defaultModel, "gpt-4o-mini")
        XCTAssertEqual(TranslationService.APIProvider.custom.defaultModel, "")
        XCTAssertEqual(TranslationService.APIProvider.localAI.defaultModel, "")
    }

    func testAPIProviderRequiresAPIKey() {
        XCTAssertFalse(TranslationService.APIProvider.localAI.requiresAPIKey)
        XCTAssertTrue(TranslationService.APIProvider.openrouter.requiresAPIKey)
        XCTAssertTrue(TranslationService.APIProvider.openai.requiresAPIKey)
        XCTAssertTrue(TranslationService.APIProvider.custom.requiresAPIKey)
    }

    func testAPIProviderRawValues() {
        XCTAssertEqual(TranslationService.APIProvider(rawValue: "openrouter"), .openrouter)
        XCTAssertEqual(TranslationService.APIProvider(rawValue: "openai"), .openai)
        XCTAssertEqual(TranslationService.APIProvider(rawValue: "custom"), .custom)
        XCTAssertEqual(TranslationService.APIProvider(rawValue: "localai"), .localAI)
        XCTAssertNil(TranslationService.APIProvider(rawValue: "invalid"))
    }

    // MARK: - TranslationLevel

    func testTranslationLevelSystemPrompts() {
        // Japanese prompts
        let generalJa = TranslationService.TranslationLevel.general.systemPrompt(for: .japanese)
        XCTAssertTrue(generalJa.contains("現代語訳"))
        XCTAssertTrue(generalJa.contains("解説"))

        let studentJa = TranslationService.TranslationLevel.student.systemPrompt(for: .japanese)
        XCTAssertTrue(studentJa.contains("語注"))

        let researcherJa = TranslationService.TranslationLevel.researcher.systemPrompt(for: .japanese)
        XCTAssertTrue(researcherJa.contains("直訳"))
        XCTAssertTrue(researcherJa.contains("語釈"))
        XCTAssertTrue(researcherJa.contains("解題"))

        // English prompts
        let generalEn = TranslationService.TranslationLevel.general.systemPrompt(for: .english)
        XCTAssertTrue(generalEn.contains("Translation"))
        XCTAssertTrue(generalEn.contains("Commentary"))

        let studentEn = TranslationService.TranslationLevel.student.systemPrompt(for: .english)
        XCTAssertTrue(studentEn.contains("Vocabulary"))

        let researcherEn = TranslationService.TranslationLevel.researcher.systemPrompt(for: .english)
        XCTAssertTrue(researcherEn.contains("Literal Translation"))
        XCTAssertTrue(researcherEn.contains("Glossary"))
        XCTAssertTrue(researcherEn.contains("Bibliographic Note"))
    }

    func testTranslationLevelRawValues() {
        XCTAssertEqual(TranslationService.TranslationLevel(rawValue: "general"), .general)
        XCTAssertEqual(TranslationService.TranslationLevel(rawValue: "student"), .student)
        XCTAssertEqual(TranslationService.TranslationLevel(rawValue: "researcher"), .researcher)
        XCTAssertNil(TranslationService.TranslationLevel(rawValue: "invalid"))
    }

    // MARK: - TargetLanguage

    func testTargetLanguageRawValues() {
        XCTAssertEqual(TranslationService.TargetLanguage(rawValue: "ja"), .japanese)
        XCTAssertEqual(TranslationService.TargetLanguage(rawValue: "en"), .english)
        XCTAssertNil(TranslationService.TargetLanguage(rawValue: "fr"))
    }

    // MARK: - TranslationError

    func testTranslationErrorDescriptions() {
        XCTAssertNotNil(TranslationService.TranslationError.noAPIKey.errorDescription)
        XCTAssertNotNil(TranslationService.TranslationError.textTooLong.errorDescription)
        XCTAssertNotNil(TranslationService.TranslationError.invalidResponse.errorDescription)
        XCTAssertNotNil(TranslationService.TranslationError.localAIUnavailable.errorDescription)

        let networkError = TranslationService.TranslationError.networkError("timeout")
        XCTAssertEqual(networkError.errorDescription, "timeout")

        let serverError = TranslationService.TranslationError.serverError(429, "rate limit")
        XCTAssertTrue(serverError.errorDescription!.contains("429"))
        XCTAssertTrue(serverError.errorDescription!.contains("rate limit"))
    }

    // MARK: - Constants

    func testDefaultConstants() {
        XCTAssertEqual(TranslationService.defaultEndpoint, "https://openrouter.ai/api/v1/chat/completions")
        XCTAssertEqual(TranslationService.defaultModel, "openai/gpt-4o-mini")
    }
}
