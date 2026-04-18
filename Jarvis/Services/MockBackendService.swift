import Foundation

/// Mock backend for development and previews. Simulates network latency.
actor MockBackendService: BackendService {
    func sendMessage(_ request: ChatRequest) async throws -> ChatResponse {
        try await Task.sleep(for: .seconds(1.5))
        return ChatResponse(
            reply: "At your service, sir. I've analyzed the request and prepared a response.",
            conversationId: UUID().uuidString
        )
    }

    func checkHealth() async throws -> HealthResponse {
        HealthResponse(status: "ok", version: "0.1.0-mock")
    }

    func streamResponse(_ request: ChatRequest) async throws -> AsyncThrowingStream<String, Error> {
        let words = "At your service sir. I have analyzed the request and prepared a comprehensive response.".split(separator: " ")
        return AsyncThrowingStream { continuation in
            Task {
                for word in words {
                    try await Task.sleep(for: .milliseconds(100))
                    continuation.yield(String(word) + " ")
                }
                continuation.finish()
            }
        }
    }
}
