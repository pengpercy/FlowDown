//
//  AnthropicMessagesChatClient.swift
//  FlowDown
//

import ChatClientKit
import Foundation

/// Streams chat from the Anthropic Messages API (`POST /v1/messages`).
///
/// ChatClientKit ships Chat Completions and Responses clients only; this client
/// implements its public `ChatService` protocol so the rest of the app treats all
/// three contracts the same way.
final class AnthropicMessagesChatClient: ChatService, @unchecked Sendable {
    let model: String
    let endpoint: String
    let apiKey: String
    let additionalHeaders: [String: String]
    let additionalBodyField: [String: Any]
    let session: URLSession
    let errorCollector: ErrorCollector

    enum ClientError: LocalizedError {
        case invalidURL
        case server(statusCode: Int, message: String?)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                String(localized: "The inference endpoint is not a valid URL.")
            case let .server(statusCode, message):
                if let message, !message.isEmpty {
                    String(localized: "The server responded with status \(statusCode): \(message)")
                } else {
                    String(localized: "The server responded with status \(statusCode).")
                }
            }
        }
    }

    init(
        model: String,
        endpoint: String,
        apiKey: String,
        additionalHeaders: [String: String] = [:],
        additionalBodyField: [String: Any] = [:],
        session: URLSession = .shared,
    ) {
        self.model = model
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.additionalHeaders = additionalHeaders
        self.additionalBodyField = additionalBodyField
        self.session = session
        errorCollector = Self.makeErrorCollector()
    }

    private static func makeErrorCollector() -> ErrorCollector {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { ErrorCollector() }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated { ErrorCollector() }
        }
    }

    func makeURLRequest(body: ChatRequestBody) throws -> URLRequest {
        guard let url = URL(string: endpoint), url.host != nil else { throw ClientError.invalidURL }
        let payload = try AnthropicMessagesRequestBuilder.makeBody(
            from: body,
            model: model,
            additionalBodyField: additionalBodyField,
        )
        var request = URLRequest(url: url, timeoutInterval: 600)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        CloudProvider.authorize(
            &request,
            contract: .anthropicMessages,
            token: apiKey,
            headers: additionalHeaders,
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }

    func streamingChat(body: ChatRequestBody) async throws -> AnyAsyncSequence<ChatResponseChunk> {
        let request = try makeURLRequest(body: body)
        let session = session
        let model = model
        Logger.network.infoFile("[Anthropic] starting streaming request to model: \(model) with \(body.messages.count) messages")

        let stream = AsyncThrowingStream<ChatResponseChunk, Error> { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
                        var data = Data()
                        for try await byte in bytes {
                            data.append(byte)
                            if data.count > 64 * 1024 { break }
                        }
                        throw ClientError.server(
                            statusCode: http.statusCode,
                            message: ModelManager.serverErrorMessage(from: data),
                        )
                    }
                    var decoder = AnthropicMessagesStreamDecoder()
                    // `lines` drops blank lines, and every Anthropic event carries its
                    // type inside the JSON payload, so each `data:` line stands alone.
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                        for chunk in try decoder.consume(data: payload) {
                            continuation.yield(chunk)
                        }
                    }
                    for chunk in decoder.finish() {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    Logger.network.errorFile("[Anthropic] streaming request failed: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return AnyAsyncSequence(stream)
    }
}
