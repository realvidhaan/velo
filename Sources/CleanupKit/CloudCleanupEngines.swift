import Foundation

/// Groq free-tier cleanup (default when an API key is configured). Fast and
/// smart, but sends transcript text to the cloud.
public struct GroqCleanupEngine: CleanupEngine {
    public let displayName = "Groq (cloud)"
    private let client: OpenAICompatibleClient
    private let timeout: TimeInterval

    public init(apiKey: String?, model: String = "llama-3.1-8b-instant", timeout: TimeInterval = 2.5) {
        self.client = OpenAICompatibleClient(
            baseURL: OpenAICompatibleClient.groqBaseURL,
            apiKey: apiKey,
            model: model
        )
        self.timeout = timeout
    }

    public func isAvailable() async -> Bool {
        client.apiKey?.isEmpty == false
    }

    public func cleanup(_ request: CleanupRequest) async throws -> String {
        guard await isAvailable() else { throw CleanupError.unavailable }
        return try await client.complete(
            system: CleanupPrompt.system(dictionary: request.dictionary, appHint: request.appHint, style: request.style),
            user: CleanupPrompt.user(request.raw),
            examples: request.examples,
            temperature: 0,
            maxTokens: max(64, request.raw.count),
            timeout: timeout
        )
    }
}

/// Fully-local cleanup via Ollama's OpenAI-compatible endpoint. Requires Ollama
/// running locally with the configured model pulled.
public struct OllamaCleanupEngine: CleanupEngine {
    public let displayName = "Ollama (local)"
    private let client: OpenAICompatibleClient
    private let timeout: TimeInterval
    private let baseURL: URL

    public init(model: String = "llama3.2", host: String = "http://localhost:11434", timeout: TimeInterval = 8) {
        self.baseURL = URL(string: host)!
        self.client = OpenAICompatibleClient(
            baseURL: baseURL.appendingPathComponent("v1"),
            apiKey: nil,
            model: model
        )
        self.timeout = timeout
    }

    public func isAvailable() async -> Bool {
        // Quick reachability check against the Ollama API.
        var request = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        request.timeoutInterval = 1.0
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return false
        }
        return true
    }

    public func cleanup(_ request: CleanupRequest) async throws -> String {
        return try await client.complete(
            system: CleanupPrompt.system(dictionary: request.dictionary, appHint: request.appHint, style: request.style),
            user: CleanupPrompt.user(request.raw),
            examples: request.examples,
            temperature: 0,
            maxTokens: max(64, request.raw.count),
            timeout: timeout
        )
    }
}
