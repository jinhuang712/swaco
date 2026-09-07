import Foundation
import Swaco

/// The generic implementation of the OpenAI Responses protocol: configured per
/// vendor rather than re-implemented. Any endpoint that speaks it, including an
/// app's own backend, is reached by naming a connection.
public struct ResponsesProvider: Provider {
    public let model: String
    public let connection: Connection
    public let maxOutputTokens: Int
    private let session: URLSession

    public init(
        model: String,
        connection: Connection,
        maxOutputTokens: Int = 4096,
        session: URLSession = .shared
    ) {
        self.model = model
        self.connection = connection
        self.maxOutputTokens = maxOutputTokens
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
                    http.httpBody = try await ResponsesRequest(
                        model: model, request: request, maxOutputTokens: maxOutputTokens
                    ).encoded()
                    try await connection.authentication.authenticate(&http)

                    var mapper = ResponsesEventMapper()
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
}

public extension ResponsesProvider {
    /// The body this provider would send for a request. Public so the
    /// conformance suite and a vendor's fixtures can check conversion without
    /// opening a connection.
    func encodedRequestForTesting(_ request: ModelRequest) async throws -> Data {
        try await ResponsesRequest(model: model, request: request, maxOutputTokens: maxOutputTokens).encoded()
    }
}
