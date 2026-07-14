import Foundation

/// Minimal client for any OpenAI-compatible `/chat/completions` endpoint. Powers
/// both the Groq (cloud) and Ollama (localhost) cleanup engines.
public struct OpenAICompatibleClient: Sendable {
    /// Groq's OpenAI-compatible base URL, shared by the cleanup and command engines.
    public static let groqBaseURL = URL(string: "https://api.groq.com/openai/v1")!

    public let baseURL: URL
    public let apiKey: String?
    public let model: String

    public init(baseURL: URL, apiKey: String?, model: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
    }

    public func complete(
        system: String,
        user: String,
        temperature: Double = 0,
        maxTokens: Int? = nil,
        timeout: TimeInterval = 2.5
    ) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        var body: [String: Any] = [
            "model": model,
            "temperature": temperature,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
        if let maxTokens { body["max_tokens"] = maxTokens }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CleanupError.badResponse
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw CleanupError.badResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
