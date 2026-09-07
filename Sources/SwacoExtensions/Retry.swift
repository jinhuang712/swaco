import Foundation
import Swaco

/// Tries a failed request again, backing off, for the failures that are worth
/// trying again: a vendor that asked us to wait, a network that came and went.
///
/// What is worth trying again is a fact the failing side declares, through
/// `TransientFailure` in the core, and this extension reads. An app that
/// disagrees passes its own rule; nothing here is a policy of swaco's beyond
/// believing what a failure says about itself.
public struct Retry: Extension {
    public let name = "retry"
    private let limit: Int
    private let first: Duration
    private let worthRetrying: @Sendable (any Error) -> Bool

    /// - Parameters:
    ///   - limit: how many attempts in all, the first one included.
    ///   - first: how long to wait before the second attempt; each wait after
    ///     that doubles.
    ///   - worthRetrying: which failures to try again. The default is any
    ///     failure that declared itself transient, plus the ones `URLError`
    ///     names, and nothing else.
    public init(
        limit: Int = 3,
        first: Duration = .seconds(1),
        worthRetrying: @Sendable @escaping (any Error) -> Bool = Retry.transientNetworkFailure
    ) {
        self.limit = limit
        self.first = first
        self.worthRetrying = worthRetrying
    }

    public func requestFailed(
        _ error: any Error,
        attempt: Int,
        in context: ExtensionContext
    ) async -> Recovery {
        guard attempt < limit, worthRetrying(error) else { return .giveUp }
        // A vendor's own number beats our guess; otherwise 1, 2, 4 …
        if let asked = error.retryAfter { return .retry(after: asked) }
        return .retry(after: first * Int(pow(2, Double(attempt - 1))))
    }

    /// Anything that declared itself worth another go, and the network
    /// failures `URLError` names. Anything else is the app's to name.
    public static let transientNetworkFailure: @Sendable (any Error) -> Bool = { error in
        if error.isTransient { return true }
        guard let url = error as? URLError else { return false }
        return [
            .timedOut, .cannotConnectToHost, .networkConnectionLost,
            .notConnectedToInternet, .dnsLookupFailed, .cannotFindHost,
            .internationalRoamingOff, .callIsActive, .dataNotAllowed,
        ].contains(url.code)
    }
}
