import Foundation
import VoiceDeskLogic

/// Non-live xAI chat completion for a single email. Falls back to the
/// extractive heuristic — never invents when the body is missing or the call fails.
struct GrokEmailSummarizer: EmailSummarizing, @unchecked Sendable {
    var apiKey: String
    var model: String
    var fallback: HeuristicEmailSummarizer
    var session: URLSession
    var timeout: TimeInterval

    init(
        apiKey: String,
        model: String = EmailSummary.defaultTextModel,
        fallback: HeuristicEmailSummarizer = HeuristicEmailSummarizer(),
        session: URLSession = .shared,
        timeout: TimeInterval = 12
    ) {
        self.apiKey = apiKey
        self.model = model
        self.fallback = fallback
        self.session = session
        self.timeout = timeout
    }

    static func makeDefault() -> any EmailSummarizing {
        if let key = VoiceDeskSecrets.xaiAPIKey {
            return GrokEmailSummarizer(apiKey: key, model: VoiceDeskSecrets.textModel)
        }
        return HeuristicEmailSummarizer()
    }

    func summarize(_ request: EmailSummaryRequest) async -> String {
        let grounded = EmailSummary.heuristic(request)
        guard !request.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return grounded
        }
        do {
            let generated = try await complete(request)
            let cleaned = EmailSummary.scrubUIChrome(generated)
            if cleaned.isEmpty || EmailSummary.containsUIChrome(cleaned) {
                return grounded
            }
            return cleaned
        } catch {
            return grounded
        }
    }

    private func complete(_ request: EmailSummaryRequest) async throws -> String {
        var urlRequest = URLRequest(url: URL(string: EmailSummary.chatCompletionsURL)!)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "temperature": 0.2,
            "max_tokens": 220,
            "messages": [
                ["role": "system", "content": EmailSummary.systemPrompt],
                ["role": "user", "content": EmailSummary.userPrompt(request)]
            ]
        ])
        let (data, response) = try await session.data(for: urlRequest)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let content = EmailSummary.chatCompletionContent(from: json) else {
            throw URLError(.cannotParseResponse)
        }
        return content
    }
}
