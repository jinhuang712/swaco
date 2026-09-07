import Foundation
import Swaco
import SwacoAI

/// Anthropic, and any endpoint that speaks its Messages protocol. A thin
/// target over the shared machinery: the vendor's endpoint, its header, and
/// nothing more.
public enum Anthropic {
    public static let messagesEndpoint = "https://api.anthropic.com/v1/messages"
    /// The vendor names its key header rather than using a bearer token.
    public static let keyHeader = "x-api-key"

    /// Anthropic itself.
    public static func messages(
        model: String,
        apiKey: String,
        maxTokens: Int = 4096
    ) -> MessagesProvider {
        MessagesProvider(
            model: model,
            connection: Connection(
                endpoint: messagesEndpoint,
                authentication: .apiKey(apiKey, header: keyHeader)
            ),
            maxTokens: maxTokens
        )
    }

    /// Any other endpoint that speaks the same protocol: a gateway, a vendor
    /// behind one, or the app's own backend.
    public static func compatible(
        model: String,
        endpoint: String,
        authentication: Authentication,
        headers: [String: String] = [:],
        capabilities: ModelCapabilities = ModelCapabilities(tools: true, vision: true, reasoning: true),
        maxTokens: Int = 4096
    ) -> MessagesProvider {
        MessagesProvider(
            model: model,
            connection: Connection(endpoint: endpoint, authentication: authentication, headers: headers),
            capabilities: capabilities,
            maxTokens: maxTokens
        )
    }
}
