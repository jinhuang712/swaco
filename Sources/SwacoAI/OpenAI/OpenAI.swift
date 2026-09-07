import Foundation
import Swaco
import SwacoAI

/// OpenAI, and any endpoint that speaks its Responses protocol. A thin target
/// over the shared machinery: the vendor's endpoint and nothing more.
public enum OpenAI {
    public static let responsesEndpoint = "https://api.openai.com/v1/responses"

    /// OpenAI itself.
    public static func responses(
        model: String,
        authentication: Authentication,
        maxOutputTokens: Int = 4096
    ) -> ResponsesProvider {
        ResponsesProvider(
            model: model,
            connection: Connection(endpoint: responsesEndpoint, authentication: authentication),
            maxOutputTokens: maxOutputTokens
        )
    }

    /// The older of the two shapes, and the one most other vendors copied.
    /// Reaches far more models than the newer one does.
    public static func chatCompletions(
        model: String,
        endpoint: String = "https://api.openai.com/v1/chat/completions",
        authentication: Authentication,
        headers: [String: String] = [:],
        capabilities: ModelCapabilities = .text,
        maxTokens: Int = 4096
    ) -> ChatCompletionsProvider {
        ChatCompletionsProvider(
            model: model,
            connection: Connection(endpoint: endpoint, authentication: authentication, headers: headers),
            capabilities: capabilities,
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
        maxOutputTokens: Int = 4096
    ) -> ResponsesProvider {
        ResponsesProvider(
            model: model,
            connection: Connection(endpoint: endpoint, authentication: authentication, headers: headers),
            maxOutputTokens: maxOutputTokens
        )
    }
}
