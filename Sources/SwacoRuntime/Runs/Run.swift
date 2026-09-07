import Foundation
import Swaco

/// swaco's unit of work: an `Agent` loop with every event recorded to a store
/// as it happens, under a name the app can find again.
///
/// A run needs no session. An app with no history uses runs alone.
public struct Run: Sendable {
    /// Where this run's events are recorded. A session's runs share one.
    public let group: GroupID
    private let agent: Agent
    private let store: any EventStore

    public init(group: GroupID = Run.newGroup(), agent: Agent, store: any EventStore) {
        self.group = group
        self.agent = agent
        self.store = store
    }

    public static func newGroup() -> GroupID { GroupID(UUID().uuidString) }

    /// Starts a loop from something that arrived.
    ///
    /// Every event is recorded before it is handed on, so an app never sees an
    /// event that is not yet kept, and a log never misses one the app acted on.
    public func start(_ inbound: InboundEvent) -> AsyncThrowingStream<Event, any Error> {
        record(agent.run(inbound))
    }

    /// Starts a loop from what a person typed.
    public func start(_ text: String) -> AsyncThrowingStream<Event, any Error> {
        start(.person(text))
    }

    /// Continues this run where its events stop: the context is what the log
    /// projects, and every call left without a result is handed back to its
    /// tool to be re-armed in this process.
    public func resume() -> AsyncThrowingStream<Event, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let events = try await store.read(group).map(\.event)
                    for try await event in record(agent.run(from: .continuing(events, rendering: agent.rendering))) {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Everything recorded for this run, in the order it happened.
    public func history() async throws -> [Event] {
        try await store.read(group).map(\.event)
    }

    /// What the log says happened, without running anything.
    public func state() async throws -> RunState {
        RunState(of: try await history())
    }

    private func record(_ run: AgentRun) -> AsyncThrowingStream<Event, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for await event in run.events {
                        try await store.append(event, to: group)
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    // The store failed, so the log and the app would disagree
                    // from here on. Stop rather than carry on unrecorded.
                    run.cancel()
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { reason in
                if case .cancelled = reason { run.cancel() }
                task.cancel()
            }
        }
    }
}

/// Where a run stands, read from its log rather than kept beside it.
public enum RunState: Sendable, Equatable {
    /// Nothing has happened yet.
    case idle
    /// Events stop mid-turn: the process went away while the loop was running.
    case interrupted
    /// One or more calls were issued and never answered. A person's answer is
    /// one of these.
    case awaitingResults([ToolCall])
    /// The loop stopped because a person or the system asked.
    case cancelled(CancellationOrigin)
    case failed(String)
    case finished

    public init(of events: [Event]) {
        guard !events.isEmpty else { self = .idle; return }
        let waiting = Message.unanswered(in: events)
        if !waiting.isEmpty { self = .awaitingResults(waiting); return }
        for event in events.reversed() {
            switch event {
            case .finished: self = .finished; return
            case .failed(let message): self = .failed(message); return
            case .cancelled(let origin, _): self = .cancelled(origin); return
            default: continue
            }
        }
        self = .interrupted
    }
}
