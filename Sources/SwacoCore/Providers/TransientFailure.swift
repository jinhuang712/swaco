import Foundation

/// A failure that may pass.
///
/// Whether a failure is worth another go is a fact about the failure, and the
/// side that knows it is the one that made it: a provider knows that a vendor
/// said to wait, an app's backend knows its own outages. So the fact is
/// declared here, in the vocabulary both sides share, and read by whoever
/// decides what to do about it.
///
/// Deciding is not swaco's. The retry extension reads this and an app's rule
/// may ignore it; nothing in the loop acts on it by itself.
public protocol TransientFailure: Error {
    /// Whether this particular failure may pass. The same type is often both:
    /// a vendor saying to wait is transient, a vendor saying the request was
    /// wrong is not.
    var isTransient: Bool { get }

    /// How long the failure said to wait, where it said. A vendor's own
    /// number beats anybody's guess.
    var retryAfter: Duration? { get }
}

public extension TransientFailure {
    var retryAfter: Duration? { nil }
}

public extension Error {
    /// Whether this failure has declared itself worth another go. A failure
    /// that says nothing is not assumed to be.
    var isTransient: Bool {
        (self as? any TransientFailure)?.isTransient ?? false
    }

    /// What the failure asked us to wait, if anything.
    var retryAfter: Duration? {
        (self as? any TransientFailure)?.retryAfter
    }
}
