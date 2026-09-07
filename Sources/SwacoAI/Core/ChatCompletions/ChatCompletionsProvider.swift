import Foundation
import Swaco

/// The chat-completions protocol, configured per vendor rather than
/// re-implemented.
///
/// The older of OpenAI's two shapes, and the one most other vendors copied, so
/// it reaches far more models than the newer one does.
public struct ChatCompletionsProvider: Provider {
    public let model: String
    public let connection: Connection
    public let capabilities: ModelCapabilities
    public let maxTokens: Int
    private let session: URLSession

    public init(
        model: String,
        connection: Connection,
        capabilities: ModelCapabilities = .text,
        maxTokens: Int = 4096,
        session: URLSession = .shared
    ) {
        self.model = model
        self.connection = connection
        self.capabilities = capabilities
        self.maxTokens = maxTokens
        self.session = session
    }

    public func stream(_ request: ModelRequest) -> AsyncThrowingStream<StreamEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var http = URLRequest(url: connection.endpoint)
                    http.httpMethod = "POST"
                    http.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    http.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    for (field, value) in connection.headers {
                        http.setValue(value, forHTTPHeaderField: field)
                    }
                    http.httpBody = try await ChatCompletionsRequest(
                        model: model, request: request, maxTokens: maxTokens
                    ).encoded()
                    try await connection.authentication.authenticate(&http)

                    var mapper = ChatCompletionsEventMapper()
                    for try await event in serverSentEvents(for: http, session: session) {
                        for streamEvent in try mapper.map(event) { continuation.yield(streamEvent) }
                    }
                    // The stream is over however it ended, so the stop is
                    // said now if the vendor never got round to it.
                    for streamEvent in mapper.done() { continuation.yield(streamEvent) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The body this provider would send, without sending it.
    public func encodedRequestForTesting(_ request: ModelRequest) async throws -> Data {
        try await ChatCompletionsRequest(model: model, request: request, maxTokens: maxTokens).encoded()
    }
}
