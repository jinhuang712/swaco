import Foundation
import Testing
import Swaco
import SwacoRuntime
import SwacoTesting
import Templates

/// The templates are examples, not products, so these checks are about one
/// thing: each still works through the public doors. If one of them ever
/// needs a private path, the core is deficient and the core gets fixed.
@Suite struct TemplatesStillWork {
    @Test func aBudgetStopsTheLoopAndSaysWhy() async throws {
        // A model that would keep asking for tools forever.
        let endless = ScriptedProvider(turns: (1...10).map { turn in
            [.text("turn \(turn)"),
             .toolCall(ToolCall(id: "c\(turn)", name: "echo", arguments: "{}")),
             .stop(.toolUse)]
        })
        let run = Run(
            agent: Agent(provider: endless, tools: [Echo()], extensions: [Budget(turns: 3)]),
            store: InMemoryEventStore()
        )
        var events: [Event] = []
        for try await event in run.start("go on then") { events.append(event) }

        let turns = events.filter { if case .turnStarted = $0 { true } else { false } }
        #expect(turns.count == 3)
        #expect(events.contains(.refused(by: "budget", subject: .turn(3),
                                         reason: "the budget of 3 turns is spent")))
        #expect(!events.contains(.finished), "a budget stops the loop; it does not finish it")
    }

    /// The honest budget on a phone: what the process has left.
    @Test func aBudgetMayReadWhatTheProcessHasLeft() async throws {
        let hurried = ExecutionContext(placement: .appExtension, remainingTime: 2, personIsPresent: false)
        let run = Run(
            agent: Agent(provider: ScriptedProvider(turns: [
                [.text("one"), .toolCall(ToolCall(id: "c", name: "echo", arguments: "{}")), .stop(.toolUse)],
                [.text("two"), .stop(.endTurn)],
            ]), tools: [Echo()], extensions: [RemainingTimeBudget()], execution: hurried),
            store: InMemoryEventStore()
        )
        var events: [Event] = []
        for try await event in run.start("be quick") { events.append(event) }
        #expect(events.contains { if case .refused(by: "remaining-time", _, _) = $0 { true } else { false } })
    }

    @Test func disclosureShowsFewToolsUntilTheModelAsks() async throws {
        let catalogue = [
            ToolDefinition(name: "echo", description: "Returns its arguments", parameters: #"{"type":"object"}"#),
            ToolDefinition(name: "weather", description: "The weather for a city", parameters: #"{"type":"object"}"#),
        ]
        let revealed = ProgressiveDisclosure.Revealed()
        let discover = ProgressiveDisclosure.Discover(catalogue: catalogue, revealed: revealed)
        let seen = Requests()

        let provider = seen.watching(ScriptedProvider(turns: [
            [.toolCall(ToolCall(id: "d", name: "find_tools", arguments: #"{"need":"weather"}"#)),
             .stop(.toolUse)],
            [.text("Found it."), .stop(.endTurn)],
        ]))
        let run = Run(
            agent: Agent(provider: provider,
                         tools: [Echo(), Weather(), discover],
                         extensions: [ProgressiveDisclosure(alwaysShow: ["echo"], revealed: revealed)]),
            store: InMemoryEventStore()
        )
        var events: [Event] = []
        for try await event in run.start("what is the weather?") { events.append(event) }

        let first = await seen.all[0].tools.map(\.name).sorted()
        #expect(first == ["echo", "find_tools"], "the model starts with a few tools and a way to find more")
        let second = await seen.all[1].tools.map(\.name).sorted()
        #expect(second.contains("weather"), "what the model asked for is there on the next turn")
        #expect(events.contains(.rewritten(by: "disclosure", subject: .request)))
    }

    @Test func compactionShortensWhatIsSentAndLeavesTheLogAlone() async throws {
        let store = InMemoryEventStore()
        let seen = Requests()
        // A history longer than the limit, written as events like any other.
        var history: [Event] = [.arrived(.person("the first thing"))]
        for turn in 1...12 {
            history += [.turnStarted(turn), .text("reply \(turn)"), .turnEnded(.endTurn),
                        .arrived(.person("thing \(turn)"))]
        }
        try await store.append(history, to: "long")

        let run = Run(
            group: "long",
            agent: Agent(provider: seen.watching(ScriptedProvider.saying("Caught up.")),
                         tools: [],
                         extensions: [Compaction(limit: 10, keep: 4)]),
            store: store
        )
        for try await _ in run.resume() {}

        let sent = await seen.all[0].messages
        #expect(sent.count == 5, "one summary and the four kept messages")
        guard case .system(let summary) = sent.first else {
            Issue.record("the summary must arrive as instructions")
            return
        }
        #expect(summary.contains("the person said: the first thing"))

        // The log still has everything: compaction changes what is sent, not
        // what happened.
        let kept = try await run.history()
        #expect(kept.count > sent.count)
        #expect(kept.first == .arrived(.person("the first thing")))
    }
}

private struct Echo: Tool {
    let name = "echo", description = "Returns its arguments", access = ToolAccess.readOnly
    func execute(_ call: ToolCall, delivering: ResultDelivery) async throws -> ToolOutcome {
        .result(ToolResult(callID: call.id, content: call.arguments))
    }
}

private struct Weather: Tool {
    let name = "weather", description = "The weather for a city", access = ToolAccess.readOnly
    func execute(_ call: ToolCall, delivering: ResultDelivery) async throws -> ToolOutcome {
        .result(ToolResult(callID: call.id, content: "18C"))
    }
}

private actor Requests {
    private(set) var all: [ModelRequest] = []
    nonisolated func watching(_ provider: ScriptedProvider) -> Watching { Watching(provider, self) }
    fileprivate func note(_ request: ModelRequest) { all.append(request) }
}

private struct Watching: Provider {
    let wrapped: ScriptedProvider
    let requests: Requests
    init(_ wrapped: ScriptedProvider, _ requests: Requests) {
        self.wrapped = wrapped
        self.requests = requests
    }
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<StreamEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                await requests.note(request)
                do {
                    for try await event in wrapped.stream(request) { continuation.yield(event) }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
