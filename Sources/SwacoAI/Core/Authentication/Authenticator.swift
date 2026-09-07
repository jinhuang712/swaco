import Foundation

/// Attaches authentication to a request, and refreshes it when the vendor
/// signals that it has expired. The door a third party conforms to.
public protocol Authenticator: Sendable {
    func authenticate(_ request: inout URLRequest) async throws
}

/// The shipped authenticators, named at the call site. None is a default: the
/// app says which one it uses. A third party's own `Authenticator` reaches the
/// same APIs through `custom`.
public struct Authentication: Authenticator {
    private let apply: @Sendable (inout URLRequest) async throws -> Void

    private init(_ apply: @Sendable @escaping (inout URLRequest) async throws -> Void) {
        self.apply = apply
    }

    public func authenticate(_ request: inout URLRequest) async throws {
        try await apply(&request)
    }

    /// A static bearer token in the `Authorization` header.
    public static func bearer(_ token: String) -> Authentication {
        Authentication { $0.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    }

    /// A bearer token read from an environment variable when the request is
    /// made. Convenient for examples and command-line programs.
    public static func bearer(environment name: String) -> Authentication {
        Authentication { request in
            guard let token = ProcessInfo.processInfo.environment[name], !token.isEmpty else {
                throw AuthenticationError.missingEnvironmentVariable(name)
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    /// A static API key in a header the vendor names.
    public static func apiKey(_ key: String, header: String) -> Authentication {
        Authentication { $0.setValue(key, forHTTPHeaderField: header) }
    }

    /// An OAuth token pair, refreshed when it is about to stop working.
    ///
    /// Swaco holds no client id and runs no browser: getting the first pair
    /// is a vendor's own flow, with a web view and a registered app, and that
    /// is a companion's business or the app's. What swaco does is the dull
    /// part nobody should rewrite: attach the token, notice it is stale,
    /// exchange it, keep the new one.
    ///
    /// - Parameters:
    ///   - store: where the pair lives. The app names it.
    ///   - refresh: how this vendor exchanges a refresh token for a new pair.
    public static func oauth(
        store: any TokenStore,
        refresh: @Sendable @escaping (String) async throws -> Tokens
    ) -> Authentication {
        Authentication { request in
            guard var tokens = try await store.tokens() else {
                throw AuthenticationError.noTokens
            }
            if tokens.isStale(), let refreshToken = tokens.refresh {
                tokens = try await refresh(refreshToken)
                try await store.save(tokens)
            }
            request.setValue("Bearer \(tokens.access)", forHTTPHeaderField: "Authorization")
        }
    }

    /// The app's own scheme, for its own backend.
    public static func custom(_ authenticate: @Sendable @escaping (inout URLRequest) async throws -> Void) -> Authentication {
        Authentication(authenticate)
    }

    /// Any `Authenticator`, including a third party's.
    public static func custom(_ authenticator: any Authenticator) -> Authentication {
        Authentication { try await authenticator.authenticate(&$0) }
    }
}

public enum AuthenticationError: Error, Sendable, Equatable {
    case missingEnvironmentVariable(String)
    /// Nobody has signed in yet. Signing in is the app's flow, not swaco's.
    case noTokens
}
