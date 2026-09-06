//  HTTP client for any OpenAI-compatible chat completions API, with SSE streaming.

import Foundation
import os

// MARK: - Errors

enum HermesClientError: LocalizedError, Equatable {
    case invalidURL
    case unauthorized
    case serverUnavailable
    case decodingError(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The server URL is not valid. It must start with http:// or https://"
        case .unauthorized:
            return "The server rejected the API key."
        case .serverUnavailable:
            return "The server is unreachable."
        case .decodingError(let detail):
            return "Could not read the server response: \(detail)"
        case .networkError(let detail):
            return "Network error: \(detail)"
        }
    }
}

// MARK: - Wire format

/// One decoded chunk of an OpenAI-compatible `chat.completion.chunk` stream.
struct ChatCompletionChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
        }
        let delta: Delta?
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    let choices: [Choice]
}

/// A single line of a Server-Sent Events stream, once classified.
enum ServerSentEvent: Equatable {
    /// A content delta to append to the response.
    case token(String)
    /// The terminal `data: [DONE]` sentinel.
    case done
    /// Comments, keep-alives, blank lines and deltas carrying no content.
    case ignored
}

// MARK: - Client

@MainActor
@Observable
final class HermesClient {
    var baseURL: String
    var apiKey: String
    var isConnected: Bool = false

    /// Model name sent in the request body. Hermes ignores it; OpenAI does not.
    var model: String = "hermes-agent"

    private var streamTask: Task<Void, Never>?
    private var session: URLSession

    private nonisolated static let logger = Logger(
        subsystem: "com.desarol.hermes-voice",
        category: "HermesClient"
    )

    init(baseURL: String = "", apiKey: String = "", session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
    }

    // MARK: Health

    /// Checks that the server is alive.
    ///
    /// Tries `GET /health` first. Servers that do not implement it (OpenAI, Ollama,
    /// LM Studio) fall back to `GET /v1/models`, so "any OpenAI-compatible backend"
    /// actually holds.
    func checkHealth() async throws -> Bool {
        let base = Self.normalizedBase(baseURL)
        guard let healthURL = Self.endpoint(base: base, path: "/health") else {
            throw HermesClientError.invalidURL
        }

        do {
            let (data, response) = try await session.data(for: request(url: healthURL, method: "GET"))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            if status == 200 {
                let body = String(decoding: data, as: UTF8.self).lowercased()
                if body.contains("ok") {
                    isConnected = true
                    return true
                }
            }
            if status == 401 || status == 403 {
                isConnected = false
                throw HermesClientError.unauthorized
            }
            // /health missing or unrecognised — try the models endpoint instead.
            return try await checkModelsEndpoint(base: base)
        } catch let error as HermesClientError {
            isConnected = false
            throw error
        } catch {
            isConnected = false
            throw HermesClientError.networkError(error.localizedDescription)
        }
    }

    private func checkModelsEndpoint(base: String) async throws -> Bool {
        guard let modelsURL = Self.endpoint(base: base, path: "/v1/models") else {
            throw HermesClientError.invalidURL
        }
        let (_, response) = try await session.data(for: request(url: modelsURL, method: "GET"))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200:
            isConnected = true
            return true
        case 401, 403:
            isConnected = false
            throw HermesClientError.unauthorized
        default:
            isConnected = false
            throw HermesClientError.serverUnavailable
        }
    }

    // MARK: Streaming

    /// Streams the assistant's reply token by token.
    ///
    /// The stream finishes on `data: [DONE]`, or throws on transport/HTTP errors.
    func sendMessage(
        messages: [Message],
        systemPrompt: String?
    ) -> AsyncThrowingStream<String, Error> {
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()

        let base = Self.normalizedBase(baseURL)
        let key = apiKey
        let modelName = model
        let session = self.session

        guard let url = Self.endpoint(base: base, path: "/v1/chat/completions") else {
            continuation.finish(throwing: HermesClientError.invalidURL)
            return stream
        }

        let body: Data
        do {
            body = try Self.makeRequestBody(
                model: modelName,
                messages: messages,
                systemPrompt: systemPrompt
            )
        } catch {
            continuation.finish(throwing: HermesClientError.decodingError(error.localizedDescription))
            return stream
        }

        streamTask?.cancel()
        let task = Task {
            await Self.pump(
                session: session,
                url: url,
                apiKey: key,
                body: body,
                continuation: continuation
            )
        }
        streamTask = task
        continuation.onTermination = { _ in task.cancel() }

        return stream
    }

    /// Test seam: swaps the transport so tests can stub the network.
    func replaceSession(_ session: URLSession) {
        self.session = session
    }

    /// Aborts the in-flight streaming request, if any.
    func cancel() {
        streamTask?.cancel()
        streamTask = nil
    }

    // MARK: - Network plumbing

    private nonisolated static func pump(
        session: URLSession,
        url: URL,
        apiKey: String,
        body: Data,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 120

        do {
            let (bytes, response) = try await session.bytes(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            guard status == 200 else {
                // Drain a little of the body so the error message is useful.
                var detail = ""
                for try await line in bytes.lines where detail.count < 500 {
                    detail += line
                }
                logger.error("Chat completions failed: HTTP \(status) \(detail, privacy: .public)")
                switch status {
                case 401, 403:
                    continuation.finish(throwing: HermesClientError.unauthorized)
                case 404, 500...599:
                    continuation.finish(throwing: HermesClientError.serverUnavailable)
                default:
                    continuation.finish(throwing: HermesClientError.networkError("HTTP \(status)"))
                }
                return
            }

            for try await line in bytes.lines {
                if Task.isCancelled {
                    continuation.finish()
                    return
                }
                switch parseSSELine(line) {
                case .token(let text):
                    continuation.yield(text)
                case .done:
                    continuation.finish()
                    return
                case .ignored:
                    continue
                }
            }
            // Stream closed without an explicit [DONE]; treat as a clean finish.
            continuation.finish()
        } catch is CancellationError {
            continuation.finish()
        } catch {
            if (error as NSError).code == NSURLErrorCancelled {
                continuation.finish()
            } else {
                continuation.finish(throwing: HermesClientError.networkError(error.localizedDescription))
            }
        }
    }

    private func request(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 5
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    // MARK: - Pure helpers (unit-tested)

    /// Strips trailing slashes so path joining never produces `//`.
    nonisolated static func normalizedBase(_ raw: String) -> String {
        var base = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") {
            base.removeLast()
        }
        return base
    }

    /// Builds an endpoint URL, rejecting anything that is not http(s).
    nonisolated static func endpoint(base: String, path: String) -> URL? {
        guard !base.isEmpty,
              let url = URL(string: base + path),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else { return nil }
        return url
    }

    /// Serialises the request body for `/v1/chat/completions`.
    nonisolated static func makeRequestBody(
        model: String,
        messages: [Message],
        systemPrompt: String?
    ) throws -> Data {
        var wire: [[String: String]] = []
        if let systemPrompt, !systemPrompt.isEmpty {
            wire.append(["role": "system", "content": systemPrompt])
        }
        for message in messages where message.role != .system {
            wire.append(["role": message.role.rawValue, "content": message.content])
        }

        let payload: [String: Any] = [
            "model": model,
            "messages": wire,
            "stream": true,
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    /// Classifies one raw line of an SSE stream.
    nonisolated static func parseSSELine(_ line: String) -> ServerSentEvent {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        // Blank lines separate events; lines starting with ':' are comments/keep-alives.
        guard !trimmed.isEmpty, !trimmed.hasPrefix(":") else { return .ignored }
        // We only care about the `data:` field; ignore `event:`, `id:`, `retry:`.
        guard trimmed.hasPrefix("data:") else { return .ignored }

        let payload = trimmed
            .dropFirst("data:".count)
            .trimmingCharacters(in: .whitespaces)

        if payload == "[DONE]" { return .done }
        guard let data = payload.data(using: .utf8) else { return .ignored }

        guard let chunk = try? JSONDecoder().decode(ChatCompletionChunk.self, from: data),
              let content = chunk.choices.first?.delta?.content,
              !content.isEmpty
        else { return .ignored }

        return .token(content)
    }
}
