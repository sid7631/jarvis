import Foundation

/// Connects to the Python FastAPI backend over HTTP.
@MainActor
final class FastAPIService: BackendService {
    let baseURL: URL
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(baseURL: URL = URL(string: "http://127.0.0.1:8000")!) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Chat

    func sendMessage(_ request: ChatRequest) async throws -> ChatResponse {
        let url = baseURL.appendingPathComponent("api/v1/chat")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try encode(request)

        let (data, response) = try await session.data(for: urlRequest)

        guard let http = response as? HTTPURLResponse else {
            throw BackendError.connectionFailed
        }
        guard (200...299).contains(http.statusCode) else {
            throw BackendError.serverError(statusCode: http.statusCode)
        }

        do {
            return try decode(ChatResponse.self, from: data)
        } catch {
            throw BackendError.decodingError
        }
    }

    // MARK: - Health

    func checkHealth() async throws -> HealthResponse {
        let url = baseURL.appendingPathComponent("api/v1/health")
        let (data, _) = try await session.data(from: url)
        return try decode(HealthResponse.self, from: data)
    }

    // MARK: - Streaming (SSE)

    func streamResponse(_ request: ChatRequest) async throws -> AsyncThrowingStream<String, Error> {
        let url = baseURL.appendingPathComponent("api/v1/chat/stream")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try encode(request)

        let (bytes, _) = try await session.bytes(for: urlRequest)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let text = String(line.dropFirst(6))
                            if text == "[DONE]" {
                                continuation.finish()
                                return
                            }
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Codable Helpers

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }
}
