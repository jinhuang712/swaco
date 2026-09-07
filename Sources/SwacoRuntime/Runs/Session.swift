import Foundation
import Swaco

/// swaco's grouping of runs into a persistent history. Optional: apps with no
/// history never touch it.
///
/// A session is a name and a store. Its runs write into one log, so the
/// history is one ordered record rather than a set of fragments to stitch.
/// Which agent serves it is not part of it: one session can be continued by
/// differently configured agents, and one configuration can serve many
/// sessions.
public struct Session: Sendable {
    public let id: GroupID
    private let store: any EventStore

    public init(id: GroupID = Session.newID(), store: any EventStore) {
        self.id = id
        self.store = store
    }

    public static func newID() -> GroupID { GroupID(UUID().uuidString) }

    /// A run in this session, served by the agent given now.
    public func run(with agent: Agent) -> Run {
        Run(group: id, agent: agent, store: store)
    }

    /// Everything this session has recorded.
    public func history() async throws -> [Event] {
        try await store.read(id).map(\.event)
    }

    /// Where the session stands, read from its log.
    public func state() async throws -> RunState {
        RunState(of: try await history())
    }

    /// Every session a store holds. Lookup, without a registry to keep in
    /// step with the log.
    public static func all(in store: any EventStore) async throws -> [Session] {
        try await store.groups().map { Session(id: $0, store: store) }
    }
}
