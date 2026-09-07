import Foundation
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
