import Foundation
import Testing
import Swaco
import SwacoRuntime
import SwacoTesting

/// A tool whose answer comes from outside, later. In a fresh process it knows
/// nothing until the loop hands the call back to it.
private actor Question: Tool {
    nonisolated let name = "ask"
    nonisolated let description = "Ask the person"
    nonisolated let access = ToolAccess.readOnly
    /// One delivery per call. Re-arming replaces it, so an answer always
    /// reaches the loop that is waiting now rather than one that is gone.
    private var deliveries: [String: ResultDelivery] = [:]
    private var asked = 0

    func execute(_ call: ToolCall, delivering delivery: ResultDelivery) async throws -> ToolOutcome {
        deliveries[call.id] = delivery
        asked += 1
        return .deferred
    }

    /// A fresh process, a fresh tool: re-arm whatever will deliver the result.
    func resume(_ call: ToolCall, delivering delivery: ResultDelivery) async throws {
        deliveries[call.id] = delivery
        asked += 1
    }

    /// What the app does when the person answers.
    func answer(_ text: String) async {
        let waiting = deliveries
        deliveries = [:]
        for (callID, delivery) in waiting {
            await delivery(ToolResult(callID: callID, content: text))
        }
    }

    var wasAsked: Bool { asked > 0 }
}

private func askingProvider() -> ScriptedProvider {
    ScriptedProvider(turns: [
        [.text("Let me check with you."),
         .toolCall(ToolCall(id: "a1", name: "ask", arguments: #"{"q":"ok?"}"#)),
         .stop(.toolUse)],
        [.text("Then we are done."), .stop(.endTurn)],
    ])
}

@Suite struct RunsRecordWhatHappens {
    @Test func everyEventIsInTheLogTheAppCanRead() async throws {
        let store = InMemoryEventStore()
        let run = Run(agent: Agent(provider: ScriptedProvider.saying("Hello."), tools: []), store: store)

        var seen: [Event] = []
        for try await event in run.start("hi") { seen.append(event) }

        #expect(seen == [.arrived(.person("hi")), .turnStarted(1), .text("Hello."),
                         .turnEnded(.endTurn), .finished])
        // What the app saw and what the store holds are the same thing.
        #expect(try await run.history() == seen)
        #expect(try await run.state() == .finished)
    }

    /// The log is the record, so the context is read off it rather than kept
    /// beside it.
    @Test func messagesAreAProjectionOfTheLog() async throws {
        let store = InMemoryEventStore()
        let run = Run(agent: Agent(provider: askingProvider(), tools: [Question()]), store: store)
        // Stop where a real process would: the tool is waiting on a person.
        for try await event in run.start("what now?") {
            if case .toolCallDeferred = event { break }
        }

        let events = try await run.history()
        #expect(Message.projection(of: events) == [
            .user("what now?"),
            .assistant(text: "Let me check with you.",
                       toolCalls: [ToolCall(id: "a1", name: "ask", arguments: #"{"q":"ok?"}"#)]),
        ])
    }

    /// Where an event came from reaches the model, so a shortcut is not
    /// mistaken for a person.
    @Test func aSourceOtherThanAPersonSaysSo() async throws {
        let store = InMemoryEventStore()
        let run = Run(agent: Agent(provider: ScriptedProvider.saying("Noted."), tools: []), store: store)
        for try await _ in run.start(InboundEvent(source: .shortcut, text: "start the day")) {}

        let messages = Message.projection(of: try await run.history())
        #expect(messages.first == .user("[shortcut] start the day"))
    }
}

@Suite struct RunsSurviveTheProcess {
    /// The whole point: a tool asked a person, the process went away, and the
    /// answer still lands in the right loop.
    @Test func aWaitOutlivesTheProcessThatStartedIt() async throws {
        let directory = URL.temporaryDirectory.appending(path: "swaco-recovery-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let group = Run.newGroup()

        // One process: the model asks, the tool defers, the process ends.
        do {
            let store = try FileEventStore(directory: directory)
            let run = Run(group: group, agent: Agent(provider: askingProvider(), tools: [Question()]), store: store)
            for try await event in run.start("shall we?") {
                if case .toolCallDeferred = event { break }
            }
        }

        // Another process: a new store over the same files, a new tool that
        // remembers nothing, and a differently made agent.
        let store = try FileEventStore(directory: directory)
        let awaiting = Run(group: group, agent: Agent(provider: askingProvider(), tools: [Question()]), store: store)
        let call = ToolCall(id: "a1", name: "ask", arguments: #"{"q":"ok?"}"#)
        #expect(try await awaiting.state() == .awaitingResults([call]))

        let question = Question()
        let resumed = Run(group: group, agent: Agent(provider: askingProvider(), tools: [question]), store: store)
        var seen: [Event] = []
        let answering = Task {
            for try await event in resumed.resume() {
                seen.append(event)
                if case .toolCallDeferred = event { await question.answer("yes") }
            }
            return seen
        }
        let events = try await answering.value

        #expect(await question.wasAsked, "the call must be handed back to its tool")
        #expect(events.contains(.toolResultArrived(ToolResult(callID: "a1", content: "yes"))))
        #expect(events.last == .finished)
        #expect(try await resumed.state() == .finished)

        // The whole story is in one log, across both processes.
        let history = try await resumed.history()
        #expect(history.first == .arrived(.person("shall we?")))
        #expect(Message.projection(of: history).last == .assistant(text: "Then we are done.", toolCalls: []))
    }

    /// A log that stops mid-turn is interrupted, not finished and not failed.
    @Test func aLogThatStopsMidTurnSaysSo() async throws {
        let events: [Event] = [.arrived(.person("hi")), .turnStarted(1), .text("half a rep")]
        #expect(RunState(of: events) == .interrupted)
        #expect(RunState(of: []) == .idle)
        #expect(RunState(of: events + [.failed("network")]) == .failed("network"))
        #expect(RunState(of: events + [.cancelled(.person, partial: "half a rep")]) == .cancelled(.person))
    }
}

@Suite struct SessionsHoldHistory {
    /// Configuration and history are separate: one session, two differently
    /// made agents, one record.
    @Test func oneSessionServedByTwoAgents() async throws {
        let store = InMemoryEventStore()
        let session = Session(store: store)

        for try await _ in session.run(with: Agent(provider: ScriptedProvider.saying("First."), tools: [])).start("one") {}
        for try await _ in session.run(with: Agent(provider: ScriptedProvider.saying("Second."), tools: [])).start("two") {}

        let messages = Message.projection(of: try await session.history())
        #expect(messages == [
            .user("one"), .assistant(text: "First.", toolCalls: []),
            .user("two"), .assistant(text: "Second.", toolCalls: []),
        ])
    }

    @Test func sessionsAreFoundThroughTheStoreTheyWereWrittenTo() async throws {
        let store = InMemoryEventStore()
        let first = Session(store: store)
        for try await _ in first.run(with: Agent(provider: ScriptedProvider.saying("hi"), tools: [])).start("a") {}

        let found = try await Session.all(in: store)
        #expect(found.map(\.id) == [first.id])
        #expect(try await found.first?.state() == .finished)
    }
}

@Suite struct KilledAfterEveryEvent {
    /// The guarantee, checked systematically rather than anecdotally: end the
    /// process after each event in turn, recover, and land in the same place
    /// every time.
    @Test func recoveryReachesTheSameEndWhereverTheProcessDies() async throws {
        let directory = URL.temporaryDirectory.appending(path: "swaco-crash-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        // A tool that answers only when the app answers it, and a desk that
        // is new in every process, like the app it belongs to.
        let question = Question()
        try await CrashReplay(
            store: { try FileEventStore(directory: directory) },
            agent: { Agent(provider: askingProvider(), tools: [question]) },
            input: .person("shall we?"),
            answering: { _ in await question.answer("yes") }
        ).verify()
    }
}
