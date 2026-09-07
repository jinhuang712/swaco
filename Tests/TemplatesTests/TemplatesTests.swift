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

@Suite struct BudgetsCount {
    /// Tokens are counted by whoever cares, which is the template, not swaco.
    @Test func aTokenBudgetStopsTheLoop() async throws {
        let costly = ScriptedProvider(turns: (1...5).map { turn in
            [.text("turn \(turn)"),
             .usage(Usage(inputTokens: 400, outputTokens: 200)),
             .toolCall(ToolCall(id: "c\(turn)", name: "echo", arguments: "{}")),
             .stop(.toolUse)]
        })
        let run = Run(
            agent: Agent(provider: costly, tools: [Echo()], extensions: [Budget(tokens: 1_000)]),
            store: InMemoryEventStore()
        )
        var events: [Event] = []
        for try await event in run.start("spend it") { events.append(event) }

        // 600 after one turn, 1200 after two: it stops at the end of the second.
        #expect(events.filter { if case .turnStarted = $0 { true } else { false } }.count == 2)
        #expect(events.contains { if case .refused(by: "budget", _, let reason) = $0 {
            reason.contains("tokens is spent")
        } else { false } })
        // And what each turn cost is in the log, for anyone who wants it.
        #expect(events.filter { if case .usage = $0 { true } else { false } }.count == 2)
    }
}

@Suite struct AnAppsOwnToolsAndSets {
    /// The template shape works through the public doors: a set is handed
    /// over whole, and a single tool needs no wrapping to sit beside it.
    @Test func aSetAndALoneToolAreHandedOverTogether() async throws {
        let notes = NoteDown.Notes()
        let door = WaitForTheDoor.Door()
        let household = HouseholdTools(notes: notes, door: door)

        let agent = Agent(
            provider: ScriptedProvider(turns: [
                [.toolCall(ToolCall(id: "n", name: "note_down", arguments: #"{"note":"milk"}"#)),
                 .stop(.toolUse)],
                [.text("Written down."), .stop(.endTurn)],
            ]),
            toolsets: [household, Echo()],
            extensions: [DropDuplicateTools()]
        )
        let run = Run(agent: agent, store: InMemoryEventStore())
        var events: [Event] = []
        for try await event in run.start("note milk") { events.append(event) }

        #expect(events.contains(.toolResultArrived(ToolResult(callID: "n", content: "written down"))))
        #expect(await notes.all == ["milk"])
        #expect(events.last == .finished)
    }

    /// Part of a set, at the granularity of a tool.
    @Test func anAppMayTakePartOfASet() {
        let household = HouseholdTools(notes: NoteDown.Notes(), door: WaitForTheDoor.Door())
        #expect(household.tools.map(\.name).sorted() == ["note_down", "wait_for_the_door"])
        #expect(household.only(["note_down"]).tools.map(\.name) == ["note_down"])
        #expect(household.except(["note_down"]).tools.map(\.name) == ["wait_for_the_door"])
        // A rule reads what a tool declared about itself and nothing else.
        #expect(household.keeping { $0.access == .readOnly }.tools.map(\.name) == ["wait_for_the_door"])
    }

    /// A tool is a toolset of one, so nothing has to be wrapped to fit.
    @Test func aSingleToolIsASetOfOne() {
        let echo = Echo()
        #expect(echo.tools.count == 1)
        #expect(echo.tools[0].name == "echo")
        // And a list of sets is just its tools, with a duplicate name dropped
        // rather than left to shadow another at call time.
        let sets: [any ToolSet] = [echo, Echo(), HouseholdTools(notes: .init(), door: .init())]
        #expect(sets.tools.map(\.name).sorted() == ["echo", "note_down", "wait_for_the_door"])
    }

    /// The pair that lets a wait outlive a process, in a template an app copies.
    @Test func aDeferredToolInATemplateSurvivesARelaunch() async throws {
        let directory = URL.temporaryDirectory.appending(path: "swaco-door-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let group = Run.newGroup()
        let script = ScriptedProvider(turns: [
            [.toolCall(ToolCall(id: "d", name: "wait_for_the_door", arguments: "{}")), .stop(.toolUse)],
            [.text("Someone came."), .stop(.endTurn)],
        ])

        do {
            let run = Run(group: group,
                          agent: Agent(provider: script, toolsets: [WaitForTheDoor(door: .init())]),
                          store: try FileEventStore(directory: directory))
            for try await event in run.start("tell me when someone arrives") {
                if case .toolCallDeferred = event { break }
            }
        }

        // A new process: a new door that remembers nothing.
        let door = WaitForTheDoor.Door()
        let run = Run(group: group,
                      agent: Agent(provider: script, toolsets: [WaitForTheDoor(door: door)]),
                      store: try FileEventStore(directory: directory))
        var events: [Event] = []
        for try await event in run.resume() {
            events.append(event)
            if case .toolCallDeferred = event { await door.opened(by: "the postman") }
        }
        #expect(events.contains(.toolResultArrived(
            ToolResult(callID: "d", content: "opened by the postman"))))
        #expect(events.last == .finished)
    }
}
