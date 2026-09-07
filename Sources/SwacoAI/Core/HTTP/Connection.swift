import Foundation
import Swaco

/// Where a provider sends its requests and how they are authenticated.
/// Everything is passed explicitly in code: no configuration files, no
/// environment lookups except the ones an authenticator names.
public struct Connection: Sendable {
    public let endpoint: URL
    public let authentication: Authentication
    /// Headers every request carries, for endpoints that need their own.
    public let headers: [String: String]

    public init(endpoint: URL, authentication: Authentication, headers: [String: String] = [:]) {
        self.endpoint = endpoint
        self.authentication = authentication
        self.headers = headers
    }

    public init(endpoint: String, authentication: Authentication, headers: [String: String] = [:]) {
        guard let url = URL(string: endpoint) else { preconditionFailure("not a URL: \(endpoint)") }
        self.init(endpoint: url, authentication: authentication, headers: headers)
    }
}

/// What went wrong between swaco and a vendor.
public enum ProviderError: Error, Sendable, Equatable {
    case http(status: Int, body: String)
    case vendor(type: String, message: String)
    case malformed(String)
    /// A part pointed at bytes and the request named no store to fetch them
    /// from. The app names the store; swaco does not choose one.
    case noContentStore(ContentReference)
}
