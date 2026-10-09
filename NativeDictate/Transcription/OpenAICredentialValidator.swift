import Foundation

struct OpenAICredentialValidator: Sendable {
    private let endpoint: URL
    private let session: URLSession

    init(
        endpoint: URL = URL(string: "https://api.openai.com/v1/models")!,
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.session = session
    }

    func validate(apiKey: String) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw TranscriptionProviderError.invalidResponse
        }
        guard (200...299).contains(response.statusCode) else {
            let message = response.statusCode == 401
                ? "The API key was rejected by OpenAI."
                : HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
            throw TranscriptionProviderError.server(statusCode: response.statusCode, message: message)
        }
    }
}
