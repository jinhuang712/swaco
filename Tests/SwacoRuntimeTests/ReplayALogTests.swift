import Foundation
import Testing
import Swaco
import SwacoRuntime
import SwacoTesting

@Suite struct ABugReportIsALog {
    /// Somebody sends a log. Reading it is one thing; running it again is
    /// another, and this is the one that finds bugs.
    @Test func alogFromSomebodyElseRunsAgainWithNothingElseToHand() async throws {
        // What happened, once, somewhere else.
        let theirs = InMemoryEventStore()
        let original = Run(
            agent: Agent(
                provider: ScriptedProvider(turns: [
                    [.text("Looking it up."),
                     .toolCall(ToolCall(id: "c1", name: "weather", arguments: #"{"city":"Paris"}"#)),
                     .usage(Usage(inputTokens: 40, outputTokens: 9)),
                     .stop(.toolUse)],
                    [.text("18C and sunny in Paris."), .stop(.endTurn)],
                ]),
                tools: [Weather()]
            ),
            store: theirs
        )
        for try await _ in original.start("weather in Paris?") {}
        let report = try await original.history()

        // All we have is that log: no vendor, no key, no calendar, no person.
        let events = report
        let arrival = try #require(ReplayingALog.arrival(in: events))
        let again = Run(
            agent: Agent(
                provider: ReplayingALog.provider(for: events),
                tools: ReplayingALog.tools(in: events)
            ),
            store: InMemoryEventStore()
        )
        var replayed: [Event] = []
        for try await event in again.start(arrival) { replayed.append(event) }

        // What the model would see is the same, which is what reproducing means.
        #expect(Message.projection(of: replayed) == Message.projection(of: events))
        #expect(RunState(of: replayed) == RunState(of: events))
        #expect(replayed.last == .finished)
    }

    /// The tools of a bug report are not to hand, so the log answers for them.
    @Test func atoolIsAnsweredFromTheLogRatherThanRun() async throws {
        let events: [Event] = [
            .arrived(.person("what is on?")),
            .turnStarted(1),
            .toolCallIssued(ToolCall(id: "c1", name: "calendar", arguments: "{}")),
            .turnEnded(.toolUse),
            .toolResultArrived(ToolResult(callID: "c1", content: "lunch at one")),
            .turnStarted(2),
            .text("Lunch at one."),
            .turnEnded(.endTurn),
            .finished,
        ]
        let tools = ReplayingALog.tools(in: events)
        #expect(tools.map(\.name) == ["calendar"])

        let again = Run(
            agent: Agent(provider: ReplayingALog.provider(for: events), tools: tools),
            store: InMemoryEventStore()
        )
        var replayed: [Event] = []
        for try await event in again.start(.person("what is on?")) { replayed.append(event) }
        #expect(replayed.contains { event in
            if case .toolResultArrived(let result) = event { result.content == "lunch at one" }
            else { false }
        })
        #expect(replayed.last == .finished)
    }

    /// A log that stops mid-turn replays to the same place it stopped, rather
    /// than inventing an ending.
    @Test func alogThatStopsMidTurnStopsThereAgain() async throws {
        let events: [Event] = [
            .arrived(.person("hello")),
            .turnStarted(1),
            .text("half a rep"),
        ]
        let again = Run(
            agent: Agent(provider: ReplayingALog.provider(for: events),
                         tools: ReplayingALog.tools(in: events)),
            store: InMemoryEventStore()
        )
        var replayed: [Event] = []
        for try await event in again.start(.person("hello")) { replayed.append(event) }
        #expect(replayed.contains(.text("half a rep")))
        // The recorded turn never ended, so the replay ends the loop rather
        // than making something up.
        #expect(replayed.last == .finished)
    }
}

private struct Weather: Tool {
    let name = "weather", description = "Weather for a city", access = ToolAccess.readOnly
    func execute(_ call: ToolCall, delivering: ResultDelivery) async throws -> ToolOutcome {
        .result(ToolResult(callID: call.id, content: "18C and sunny"))
    }
}
