import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers

/// Inference owns no downloader or HTTP client. Only a completed local snapshot can be loaded.
actor MLXRuntime {
    static let maxInputTokens = 6_000
    private var container: ModelContainer?
    private var lastInputTokenCount: Int?

    func load(directory: URL) async throws {
        container = nil
        MLX.Memory.clearCache()
        MLX.Memory.cacheLimit = 256 * 1_024 * 1_024
        container = try await LLMModelFactory.shared.loadContainer(from: directory, using: LocalTokenizerLoader())
    }

    func unload() {
        container = nil
        lastInputTokenCount = nil
        MLX.Memory.clearCache()
    }

    func measuredInputTokens() -> Int? { lastInputTokenCount }

    func response(systemPrompt: String, userText: String, history: [WorkspaceMessage] = []) async throws -> AsyncThrowingStream<Generation, Error> {
        guard let container else { throw ModelLibraryError.message("Es ist kein MLX-Modell geladen.") }
        var messages: [[String: any Sendable]] = []
        if !systemPrompt.isEmpty { messages.append(["role": "system", "content": systemPrompt]) }
        messages.append(contentsOf: history.map { message in
            ["role": message.role == .user ? "user" : "assistant", "content": message.text]
        })
        messages.append(["role": "user", "content": userText])
        let templateMessages = messages
        let additionalContext: [String: any Sendable] = ["enable_thinking": false]
        let tokenCount = try await container.perform { context in
            try context.tokenizer.applyChatTemplate(
                messages: templateMessages,
                tools: nil,
                additionalContext: additionalContext
            ).count
        }
        lastInputTokenCount = tokenCount
        guard tokenCount <= Self.maxInputTokens else {
            throw ModelLibraryError.message("Der Chatkontext ist zu groß (\(tokenCount) Eingabetokens nach Modellvorlage, maximal 6.000). Bitte kürze die Anfrage oder wähle weniger Quellen. Es werden keine Projektdateien verändert.")
        }
        // Each request gets a fresh session: no patient or project context is carried into the next request.
        let session = ChatSession(
            container,
            instructions: systemPrompt,
            history: history.map { Chat.Message(role: $0.role == .user ? .user : .assistant, content: $0.text) },
            generateParameters: GenerateParameters(maxTokens: 1536, maxKVSize: 8192, temperature: 0.2),
            additionalContext: additionalContext
        )
        return session.streamDetails(to: userText)
    }
}

private struct LocalTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        // modelFolder reads local JSON; the pretrained/network-loading overload is deliberately unused.
        let tokenizer = try await AutoTokenizer.from(modelFolder: directory)
        return LocalTokenizerBridge(upstream: tokenizer)
    }
}

private struct LocalTokenizerBridge: MLXLMCommon.Tokenizer {
    let upstream: any Tokenizers.Tokenizer
    func encode(text: String, addSpecialTokens: Bool) -> [Int] { upstream.encode(text: text, addSpecialTokens: addSpecialTokens) }
    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String { upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens) }
    func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }
    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }
    func applyChatTemplate(messages: [[String: any Sendable]], tools: [[String: any Sendable]]?, additionalContext: [String: any Sendable]?) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext)
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
