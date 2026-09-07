import Foundation
import Testing
import Swaco
import SwacoRuntime

/// Runs one piece of work over and over, ending the process after every event
/// in turn, and checks that recovery always reaches the same place as a run
/// nobody interrupted.
///
/// This is the harness behind the promise that being killed is ordinary. It is
/// public so a companion, or an app with its own tools and its own store, can
/// hold itself to the same standard.
///
/// `store` must return a **new** store over the **same** medium each time it is
/// called: that is what stands in for a new process. A store that keeps its
/// events in memory cannot show anything here, and the harness says so.
public struct CrashReplay: Sendable {
    public typealias MakeStore = @Sendable () async throws -> any EventStore
    public typealias MakeAgent = @Sendable () async throws -> Agent
    /// What the app would do when a tool says its result comes later: answer
    /// it, or leave it and let the next process deal with it.
    public typealias Answer = @Sendable (ToolCall) async -> Void

    private let store: MakeStore
    private let agent: MakeAgent
    private let answer: Answer
    private let input: InboundEvent
    /// How many times recovery may be attempted before the harness gives up.
    private let attempts: Int

    public init(
        store: @escaping MakeStore,
        agent: @escaping MakeAgent,
        input: InboundEvent,
        answering answer: @escaping Answer = { _ in },
        attempts: Int = 8
    ) {
        self.store = store
        self.agent = agent
        self.input = input
        self.answer = answer
        self.attempts = attempts
    }

    public func verify(sourceLocation: SourceLocation = #_sourceLocation) async throws {
        let group = Run.newGroup()
        let whole = try await runToTheEnd(group: group)
        #expect(whole.state == .finished,
                "the work must finish when nothing interrupts it", sourceLocation: sourceLocation)
        #expect(!whole.events.isEmpty, "the work must do something", sourceLocation: sourceLocation)

        for cut in 1...whole.events.count {
            let interrupted = Run.newGroup()
            try await runStopping(after: cut, group: interrupted)
            let recovered = try await recover(group: interrupted)

            #expect(recovered.state == whole.state,
                    "ending the process after event \(cut) left it \(recovered.state)",
                    sourceLocation: sourceLocation)
            #expect(recovered.messages == whole.messages,
                    "ending the process after event \(cut) changed what the model would see",
                    sourceLocation: sourceLocation)
            #expect(recovered.events.first == .arrived(input),
                    "a log must still begin with what arrived", sourceLocation: sourceLocation)
        }
    }

    private struct Outcome {
        let events: [Event]
        let messages: [Message]
        let state: RunState
    }

    private func outcome(of run: Run) async throws -> Outcome {
        let events = try await run.history()
        return Outcome(events: events, messages: Message.projection(of: events), state: RunState(of: events))
    }

    private func runToTheEnd(group: GroupID) async throws -> Outcome {
        let run = Run(group: group, agent: try await agent(), store: try await store())
        try await consume(run.start(input))
        return try await outcome(of: run)
    }

    private func runStopping(after cut: Int, group: GroupID) async throws {
        let run = Run(group: group, agent: try await agent(), store: try await store())
        var seen = 0
        for try await event in run.start(input) {
            seen += 1
            // The process is about to go away. Anything a tool was waiting on
            // is waiting on nobody now.
            if seen >= cut { break }
            if case .toolCallDeferred(let call) = event { await answer(call) }
        }
    }

    private func recover(group: GroupID) async throws -> Outcome {
        var run = Run(group: group, agent: try await agent(), store: try await store())
        for _ in 0..<attempts {
            if case .finished = try await run.state() { break }
            run = Run(group: group, agent: try await agent(), store: try await store())
            try await consume(run.resume())
        }
        return try await outcome(of: run)
    }

    private func consume(_ events: AsyncThrowingStream<Event, any Error>) async throws {
        for try await event in events {
            if case .toolCallDeferred(let call) = event { await answer(call) }
        }
    }
}
