import Testing
import Swaco
import SwacoTesting

/// A tool that must run on the main actor and answers at once.
@MainActor
final class ClockTool: Tool {
    nonisolated let name = "clock"
    nonisolated let description = "The current tick"
    nonisolated let access = ToolAccess.readOnly
    private(set) var ticks = 0

    func execute(_ call: ToolCall, delivering delivery: ResultDelivery) async throws -> ToolOutcome {
        MainActor.assertIsolated()
        ticks += 1
        return .result(ToolResult(callID: call.id, content: "tick \(ticks)"))
    }
}

/// A tool whose answer comes from outside, later, through the delivery.
actor AskTool: Tool {
    nonisolated let name = "ask"
    nonisolated let description = "Ask the person"
    nonisolated let access = ToolAccess.readOnly
    private var registered: [(ToolCall, ResultDelivery)] = []

    func execute(_ call: ToolCall, delivering delivery: ResultDelivery) async throws -> ToolOutcome {
        registered.append((call, delivery))
        return .deferred
    }

    /// What the app would do when the person answers.
    func answer(_ text: String) async {
        guard let (call, delivery) = registered.first else { return }
        await delivery(ToolResult(callID: call.id, content: text))
    }

    var pendingCount: Int { registered.count }
}

@Suite struct EventPairLoop {
    @Test func immediateAndDeferredToolsInOneLoop() async throws {
        let provider = ScriptedProvider(turns: [
            [.text("Checking."), .toolCall(ToolCall(id: "c1", name: "clock", arguments: "{}")),
             .toolCall(ToolCall(id: "a1", name: "ask", arguments: "{\"q\":\"ok?\"}")), .stop(.toolUse)],
            [.text("Done."), .stop(.endTurn)],
        ])
        let ask = AskTool()
        let ticker = ClockTool()
        let agent = Agent(provider: provider, tools: [ticker, ask])
        let run = agent.run("go")

        var events: [Event] = []
        for await event in run.events {
            events.append(event)
            if case .toolCallDeferred = event {
                // Nothing arrives until the person answers.
                await Task.yield()
                await ask.answer("yes")
            }
        }

        let clock = ToolCall(id: "c1", name: "clock", arguments: "{}")
        let question = ToolCall(id: "a1", name: "ask", arguments: "{\"q\":\"ok?\"}")
        #expect(events == [
            .arrived(.person("go")),
            .turnStarted(1),
            .text("Checking."),
            // A call is recorded as it arrives, before the turn ends, so the
            // log reads in the order things happened.
            .toolCallIssued(clock),
            .toolCallIssued(question),
            .turnEnded(.toolUse),
            .toolResultArrived(ToolResult(callID: "c1", content: "tick 1")),
            .toolCallDeferred(question),
            .toolResultArrived(ToolResult(callID: "a1", content: "yes")),
            .turnStarted(2),
            .text("Done."),
            .turnEnded(.endTurn),
            .finished,
        ])
    }

    @Test func personCancelsWhileDeferred() async throws {
        let provider = ScriptedProvider(turns: [
            [.text("Wait."), .toolCall(ToolCall(id: "a1", name: "ask", arguments: "{}")), .stop(.toolUse)],
        ])
        let agent = Agent(provider: provider, tools: [AskTool()])
        let run = agent.run("go")

        var events: [Event] = []
        for await event in run.events {
            events.append(event)
            if case .toolCallDeferred = event { run.cancel() }
        }

        #expect(events.last == .cancelled(.person, partial: "Wait."))
        #expect(!events.contains(.finished))
    }

    @Test func systemCancelsByCancellingTheConsumer() async throws {
        let provider = ScriptedProvider(turns: [
            [.toolCall(ToolCall(id: "a1", name: "ask", arguments: "{}")), .stop(.toolUse)],
        ])
        let agent = Agent(provider: provider, tools: [AskTool()])
        let run = agent.run("go")

        let consumer = Task<[Event], Never> {
            var events: [Event] = []
            for await event in run.events { events.append(event) }
            return events
        }
        // Give the loop time to reach the deferred wait, then cancel from outside.
        try await Task.sleep(for: .milliseconds(50))
        consumer.cancel()
        let events = await consumer.value
        #expect(events.contains(.toolCallDeferred(ToolCall(id: "a1", name: "ask", arguments: "{}"))))
        #expect(!events.contains(.finished))
    }
}
