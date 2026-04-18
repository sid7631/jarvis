import Foundation

// MARK: - Request / Response Types

struct ChatRequest: Codable, Sendable {
    let message: String
    let conversationId: String?
}

struct ChatResponse: Codable, Sendable {
    let reply: String
    let conversationId: String
}

struct HealthResponse: Codable, Sendable {
    let status: String
    let version: String
}

// MARK: - Protocol

protocol BackendService: Sendable {
    func sendMessage(_ request: ChatRequest) async throws -> ChatResponse
    func checkHealth() async throws -> HealthResponse
    func streamResponse(_ request: ChatRequest) async throws -> AsyncThrowingStream<String, Error>
}

// MARK: - Errors

enum BackendError: Error, LocalizedError {
    case serverError(statusCode: Int)
    case connectionFailed
    case decodingError

    var errorDescription: String? {
        switch self {
        case .serverError(let code): return "Server error (HTTP \(code))"
        case .connectionFailed:      return "Could not connect to backend"
        case .decodingError:         return "Failed to decode server response"
        }
    }
}
