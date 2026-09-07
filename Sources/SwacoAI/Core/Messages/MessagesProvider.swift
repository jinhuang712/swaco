import Foundation
import Swaco

/// The Messages protocol, configured per vendor rather than re-implemented.
public struct MessagesProvider: Provider {
    public let model: String
    public let connection: Connection
    public let capabilities: ModelCapabilities
    public let maxTokens: Int
    /// The version this vendor's endpoint expects in its header.
    public let version: String
    private let session: URLSession

    public init(
        model: String,
        connection: Connection,
        capabilities: ModelCapabilities = ModelCapabilities(tools: true, vision: true, reasoning: true),
        maxTokens: Int = 4096,
        version: String = "2023-06-01",
        session: URLSession = .shared
    ) {
        self.model = model
        self.connection = connection
        self.capabilities = capabilities
        self.maxTokens = maxTokens
        self.version = version
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
                    http.setValue(version, forHTTPHeaderField: "anthropic-version")
                    for (field, value) in connection.headers {
                        http.setValue(value, forHTTPHeaderField: field)
                    }
                    http.httpBody = try await MessagesRequest(
                        model: model, request: request, maxTokens: maxTokens
                    ).encoded()
                    try await connection.authentication.authenticate(&http)

                    var mapper = MessagesEventMapper()
                    for try await event in serverSentEvents(for: http, session: session) {
                        for streamEvent in try mapper.map(event) { continuation.yield(streamEvent) }
                    }
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
        try await MessagesRequest(model: model, request: request, maxTokens: maxTokens).encoded()
    }
}
