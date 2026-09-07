import Foundation
import Swaco

/// An `EventStore` that keeps events for as long as the process lives. The
/// store for tests, previews and apps with no history.
public actor InMemoryEventStore: EventStore {
    private var log: [GroupID: [StoredEvent]] = [:]

    public init() {}

    @discardableResult
    public func append(_ events: [Event], to group: GroupID) async throws -> Int {
        var stored = log[group] ?? []
        for event in events {
            stored.append(StoredEvent(position: stored.count, event: event))
        }
        log[group] = stored
        return (stored.count - 1)
    }

    public func read(_ group: GroupID, after position: Int?) async throws -> [StoredEvent] {
        let stored = log[group] ?? []
        guard let position else { return stored }
        return stored.filter { $0.position > position }
    }

    public func groups() async throws -> [GroupID] {
        Array(log.keys)
    }
}
