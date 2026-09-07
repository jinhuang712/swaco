import Foundation

/// What a log of events belongs to: one run, or one session of runs. The core
/// groups nothing itself; it carries the name whatever runs the loop chose.
public struct GroupID: Hashable, Sendable, Codable, RawRepresentable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
}

/// An event as the store holds it: what happened, and where in the order.
/// Positions increase within a group and are stable once returned.
public struct StoredEvent: Sendable, Hashable, Codable {
    public let position: Int
    public let event: Event

    public init(position: Int, event: Event) {
        self.position = position
        self.event = event
    }
}

/// Where events are recorded. The core defines the contract and holds no
/// implementation: the medium depends on the product, so the app names one.
///
/// The contract, which the conformance suite in `SwacoTesting` checks:
///
/// - **Ordered.** Appends within a group keep the order they were made in,
///   and positions increase.
/// - **Durable on return.** When `append` returns, the events are kept. A
///   store that buffers has not returned.
/// - **Read by group, in write order.** Reading a group returns its events
///   and no others.
/// - **Replay from a position.** Reading from a position returns everything
///   after it, so a reader resumes without rereading.
/// - **Preserving.** An event of a type this swaco does not know round-trips
///   unchanged.
public protocol EventStore: Sendable {
    /// Appends events to a group and returns the position of the last one.
    /// Durable when it returns.
    @discardableResult
    func append(_ events: [Event], to group: GroupID) async throws -> Int

    /// Every event of a group after `position`, in write order. A nil
    /// position means from the beginning.
    func read(_ group: GroupID, after position: Int?) async throws -> [StoredEvent]

    /// Every group the store holds.
    func groups() async throws -> [GroupID]
}

public extension EventStore {
    @discardableResult
    func append(_ event: Event, to group: GroupID) async throws -> Int {
        try await append([event], to: group)
    }

    func read(_ group: GroupID) async throws -> [StoredEvent] {
        try await read(group, after: nil)
    }
}

/// Bytes a content part points at instead of carrying, so a long history with
/// media stays cheap in memory.
public struct ContentReference: Hashable, Sendable, Codable {
    public let identifier: String
    /// The kind of bytes, as a MIME type.
    public let type: String

    public init(identifier: String, type: String) {
        self.identifier = identifier
        self.type = type
    }
}

/// Where bytes are kept. As with events, the core defines the contract and
/// holds no implementation.
///
/// - **By reference.** Storing returns a reference; loading it returns the
///   same bytes.
/// - **Durable on return.** When `store` returns, the bytes are kept.
/// - **Stable.** A reference stays valid until it is removed.
public protocol ContentStore: Sendable {
    func store(_ data: Data, type: String) async throws -> ContentReference
    func load(_ reference: ContentReference) async throws -> Data
    func remove(_ reference: ContentReference) async throws
}

/// What a store could not do.
public enum StoreError: Error, Sendable, Equatable {
    case noSuchContent(ContentReference)
    case unreadable(String)
}
