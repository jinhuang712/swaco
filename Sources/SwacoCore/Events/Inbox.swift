import Foundation

/// What is done with something that arrives while a loop is already running.
public enum Arrival: Sendable, Hashable {
    /// Into the next turn of this loop.
    case inject
    /// After this loop's current work, still in this loop.
    case queue
    /// Not this loop's business. Left for whatever runs it, which is how a
    /// new run gets started for it.
    case leave
}

/// Where an app hands the agent something that arrived.
///
/// A person typing is one source among many, and a loop that is already
/// running is the ordinary case, not the exception: a notification lands while
/// the agent is thinking, a shortcut fires mid-tool-call. The app delivers it
/// here; what happens to it is decided by the extensions the app listed, and
/// recorded either way.
public actor Inbox {
    private var arrived: [InboundEvent] = []
    private var left: [InboundEvent] = []

    public init() {}

    /// Hands the agent something. Returns at once: what becomes of it is the
    /// loop's business and the log's record.
    public func deliver(_ inbound: InboundEvent) {
        arrived.append(inbound)
    }

    /// What the loop decided was not its business, in arrival order. Whatever
    /// runs the loop reads these and starts a run for each.
    public func takeLeft() -> [InboundEvent] {
        defer { left = [] }
        return left
    }

    /// Whether anything is waiting, without taking it.
    public var isEmpty: Bool { arrived.isEmpty }

    func take() -> [InboundEvent] {
        defer { arrived = [] }
        return arrived
    }

    func leave(_ inbound: InboundEvent) {
        left.append(inbound)
    }
}

extension Array {
    /// Empties the array and returns what was in it.
    mutating func take() -> [Element] {
        defer { removeAll() }
        return self
    }
}
