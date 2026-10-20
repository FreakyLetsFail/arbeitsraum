import Foundation

struct LocalModelConfiguration: Sendable {
    var endpoint: String
    var model: String
}

protocol LocalLanguageModelEngine: Sendable {
    func availableModels(configuration: LocalModelConfiguration) async throws -> [String]
    func generate(configuration: LocalModelConfiguration, systemPrompt: String, userText: String) async throws -> String
}

enum LocalModelError: LocalizedError {
    case invalidEndpoint
    case serverResponse(String)
    case emptyResponse
    case cloudModel

    var errorDescription: String? {
        switch self {
        case .cloudModel:
            return "Cloud-Modellkennungen sind in diesem Arbeitsbereich ausgeschlossen."
        case .invalidEndpoint:
            return "Erlaubt sind ausschließlich lokale HTTP-Adressen: localhost, 127.0.0.1 oder ::1."
        case .serverResponse(let message):
            return message
        case .emptyResponse:
            return "Das lokale Modell hat keine Textantwort zurückgegeben."
        }
    }
}

/// OpenAI-compatible local server adapter. The host allowlist is enforced before every request.
struct LoopbackOpenAIEngine: LocalLanguageModelEngine {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration, delegate: LoopbackRedirectGuard(), delegateQueue: nil)
    }()

    static func isAllowedEndpoint(_ raw: String) -> Bool {
        guard let components = URLComponents(string: raw),
              components.scheme?.lowercased() == "http",
              let host = components.host?.lowercased(),
              ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host),
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            return false
        }
        return true
    }

    func availableModels(configuration: LocalModelConfiguration) async throws -> [String] {
        let url = try Self.endpoint(configuration.endpoint, suffix: "models")
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "GET"
        let (data, response) = try await Self.session.data(for: request)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(ModelListResponse.self, from: data)
        return decoded.data.map(\.id)
    }

    static func isCloudModel(_ id: String) -> Bool {
        id.lowercased().contains("cloud")
    }

    func generate(configuration: LocalModelConfiguration, systemPrompt: String, userText: String) async throws -> String {
        try await generate(configuration: configuration, systemPrompt: systemPrompt, userText: userText, history: [])
    }

    func generate(configuration: LocalModelConfiguration, systemPrompt: String, userText: String, history: [WorkspaceMessage]) async throws -> String {
        guard !Self.isCloudModel(configuration.model) else { throw LocalModelError.cloudModel }
        let url = try Self.endpoint(configuration.endpoint, suffix: "chat/completions")
        var request = URLRequest(url: url, timeoutInterval: 180)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ChatCompletionRequest(
            model: configuration.model,
            messages: [.init(role: "system", content: systemPrompt)] + history.map {
                ChatCompletionRequest.Message(role: $0.role.rawValue, content: $0.text)
            } + [.init(role: "user", content: userText)],
            temperature: 0.2,
            stream: false
        ))
        let (data, response) = try await Self.session.data(for: request)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty else {
            throw LocalModelError.emptyResponse
        }
        return content
    }

    static func endpoint(_ base: String, suffix: String) throws -> URL {
        guard Self.isAllowedEndpoint(base), var components = URLComponents(string: base) else { throw LocalModelError.invalidEndpoint }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = path.isEmpty ? "" : "/" + path
        let root = components.url?.appending(path: suffix)
        guard let root else { throw LocalModelError.invalidEndpoint }
        return root
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw LocalModelError.serverResponse("Keine gültige Antwort vom lokalen Modellserver.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8).map { String($0.prefix(600)) } ?? ""
            throw LocalModelError.serverResponse("Lokaler Modellserver meldet HTTP \(http.statusCode). \(message)")
        }
    }
}

private final class LoopbackRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // A local server must not redirect a document-bearing request to another endpoint.
        completionHandler(nil)
    }
}

private struct ModelListResponse: Decodable {
    struct Item: Decodable { let id: String }
    let data: [Item]
}

private struct ChatCompletionRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }
    let model: String
    let messages: [Message]
    let temperature: Double
    let stream: Bool
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message
    }
    let choices: [Choice]
}
