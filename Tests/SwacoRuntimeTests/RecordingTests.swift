import Foundation
import Testing
import Swaco
import SwacoRuntime
import SwacoAI
import SwacoTesting

@Suite struct RecordOnceReplayAfter {
    /// The promise: ask a model once, keep what it said, and never need a key
    /// or a network again.
    @Test func whatAModelSaidIsKeptAndPlayedBack() async throws {
        let file = URL.temporaryDirectory.appending(path: "swaco-recording-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: file) }

        // Stand-in for the real thing, asked once.
        let real = ScriptedProvider(turns: [
            [.reasoning("thinking"), .text("Checking."),
             .toolCall(ToolCall(id: "c", name: "echo", arguments: #"{"n":1}"#)),
             .usage(Usage(inputTokens: 12, outputTokens: 3, reasoningTokens: 2)),
             .stop(.toolUse)],
            [.text("Done."), .usage(Usage(inputTokens: 20, outputTokens: 2)), .stop(.endTurn)],
        ])
        let recorded = Run(
            agent: Agent(provider: Recording(real, to: file), tools: [Echo()]),
            store: InMemoryEventStore()
        )
        var live: [Event] = []
        for try await event in recorded.start("go") { live.append(event) }

        // Then again, from the file, with nothing behind it.
        let replayed = Run(
            agent: Agent(provider: try ScriptedProvider.replaying(file), tools: [Echo()]),
            store: InMemoryEventStore()
        )
        var again: [Event] = []
        for try await event in replayed.start("go") { again.append(event) }

        #expect(again == live, "a replay must reach the same events as the run it recorded")
        #expect(live.last == .finished)
        #expect(live.contains(.usage(Usage(inputTokens: 12, outputTokens: 3, reasoningTokens: 2))))
    }

    /// A recording is plain enough to read and to trim by hand.
    @Test func aRecordingIsOneObjectPerLine() async throws {
        let file = URL.temporaryDirectory.appending(path: "swaco-recording-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        let provider = Recording(ScriptedProvider.saying("Hello."), to: file)
        for try await _ in provider.stream(ModelRequest(messages: [.user("hi")], tools: [])) {}

        let lines = try String(contentsOf: file, encoding: .utf8)
            .split(separator: "\n").filter { !$0.isEmpty }
        #expect(lines.count == 2)
        #expect(lines[0].contains(#""turn":1"#))
        #expect(lines[0].contains(#""type":"text""#))
        #expect(lines[1].contains(#""type":"stop""#))
    }

    /// Every kind of streamed event survives being written down.
    @Test func everyStreamedEventSurvivesTheRecording() throws {
        let events: [StreamEvent] = [
            .text("words"),
            .reasoning("thinking"),
            .toolCall(ToolCall(id: "c", name: "echo", arguments: "{}")),
            .usage(Usage(inputTokens: 1, outputTokens: 2, cachedInputTokens: 3, reasoningTokens: 4)),
            .stop(.maxTokens),
        ]
        for event in events {
            let data = try JSONEncoder().encode(event)
            #expect(try JSONDecoder().decode(StreamEvent.self, from: data) == event)
        }
    }
}

@Suite struct HowManyAtOnce {
    /// The app says the number. Two runs, a limit of one: the second waits
    /// for the first, and both finish.
    @Test func aLimitHoldsTheSecondRunUntilTheFirstIsDone() async throws {
        let limit = RunLimit(atMost: 1)
        let store = InMemoryEventStore()
        let gate = Gate()
        let slow = Agent(provider: GatedProvider(gate: gate, saying: "First."), tools: [])
        let quick = Agent(provider: ScriptedProvider.saying("Second."), tools: [])

        let first = Task {
            var events: [Event] = []
            for try await event in Run(group: "a", agent: slow, store: store, limit: limit).start("one") {
                events.append(event)
            }
            return events
        }
        // The first run is inside its request and holding the only place.
        await gate.reached()
        let second = Task {
            var events: [Event] = []
            for try await event in Run(group: "b", agent: quick, store: store, limit: limit).start("two") {
                events.append(event)
            }
            return events
        }
        // While the first holds it, nothing else is working.
        #expect(await limit.running == 1)
        #expect(await limit.queued <= 1)

        await gate.openUp()
        let (one, two) = (try await first.value, try await second.value)
        #expect(one.contains(.text("First.")))
        #expect(two.contains(.text("Second.")))
        #expect(await limit.running == 0)
    }

    /// An app that never says is never limited.
    @Test func withNoLimitNothingIsHeld() async throws {
        let store = InMemoryEventStore()
        let agent = Agent(provider: ScriptedProvider.saying("Fine."), tools: [])
        await withTaskGroup(of: Void.self) { group in
            for name in ["a", "b", "c", "d"] {
                group.addTask {
                    let run = Run(group: GroupID(name), agent: agent, store: store)
                    try? await { for try await _ in run.start("go") {} }()
                }
            }
        }
        #expect(try await store.groups().count == 4)
    }

    private actor Gate {
        private var open = false
        private var waiting: [CheckedContinuation<Void, Never>] = []
        private var entered = false
        private var watchers: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            entered = true
            watchers.forEach { $0.resume() }
            watchers = []
            if open { return }
            await withCheckedContinuation { waiting.append($0) }
        }

        func reached() async {
            if entered { return }
            await withCheckedContinuation { watchers.append($0) }
        }

        func openUp() {
            open = true
            let queue = waiting
            waiting = []
            queue.forEach { $0.resume() }
        }
    }

    private struct GatedProvider: Provider {
        let gate: Gate
        let saying: String

        func stream(_ request: ModelRequest) -> AsyncThrowingStream<StreamEvent, any Error> {
            AsyncThrowingStream { continuation in
                let task = Task {
                    await gate.wait()
                    continuation.yield(.text(saying))
                    continuation.yield(.stop(.endTurn))
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
    }
}

@Suite struct ModelsAsData {
    @Test func theCatalogueIsAConvenienceAndFavoursNobody() {
        #expect(Catalogue.model("claude-fable-5-1")?.provider == "anthropic")
        #expect(Catalogue.model("system-language-model")?.capabilities.tools == false)
        #expect(Catalogue.models(from: "openai").allSatisfy { $0.provider == "openai" })
        #expect(Catalogue.model("a-model-nobody-told-us-about") == nil)
        // Several providers, and no first among them.
        #expect(Set(Catalogue.all.map(\.provider)).count >= 3)
    }

    /// A model an app writes down itself is no less a model.
    @Test func anAppMayDescribeItsOwn() throws {
        let ours = Model(provider: "our-backend", identifier: "house-model",
                         capabilities: ModelCapabilities(tools: true, vision: true))
        let data = try JSONEncoder().encode(ours)
        #expect(try JSONDecoder().decode(Model.self, from: data) == ours)
    }
}

private struct Echo: Tool {
    let name = "echo", description = "Returns its arguments", access = ToolAccess.readOnly
    func execute(_ call: ToolCall, delivering: ResultDelivery) async throws -> ToolOutcome {
        .result(ToolResult(callID: call.id, content: call.arguments))
    }
}
