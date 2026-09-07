import Foundation
import Testing
import Swaco
import SwacoRuntime
import SwacoTesting

/// Work that spans processes, which on a phone is most work.
@Suite struct HandingTheRestToALaterProcess {
    private func script() -> ScriptedProvider {
        ScriptedProvider(turns: [
            [.text("Looking it up."),
             .toolCall(ToolCall(id: "c1", name: "echo", arguments: #"{"n":1}"#)),
             .stop(.toolUse)],
            [.text("And again."),
             .toolCall(ToolCall(id: "c2", name: "echo", arguments: #"{"n":2}"#)),
             .stop(.toolUse)],
            [.text("All done."), .stop(.endTurn)],
        ])
    }

    /// One process does a turn, says so, and stops. The work is unfinished
    /// and the log does not pretend otherwise.
    @Test func aProcessMayDoOneTurnAndStop() async throws {
        let store = InMemoryEventStore()
        let run = Run(
            agent: Agent(provider: script(), tools: [Echo()], extensions: [Handover.afterOneTurn]),
            store: store
        )
        var events: [Event] = []
        for try await event in run.start("what is it?") { events.append(event) }

        #expect(events.contains(.handedOver(by: "handover",
                                            reason: "one turn is this process's share")))
        #expect(!events.contains(.finished), "handing over is not finishing")
        #expect(try await run.state() == .handedOver("one turn is this process's share"))
        // And the turn it did do is all there, tool result included.
        #expect(events.contains(.toolResultArrived(ToolResult(callID: "c1", content: #"{"n":1}"#))))
    }

    /// The handover survives the process boundary: another process picks the
    /// same log up and carries on where it stopped.
    @Test func theRestIsDoneByWhateverRunsNext() async throws {
        let directory = URL.temporaryDirectory.appending(path: "swaco-handover-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let group = Run.newGroup()

        // A share sheet, with seconds to spare.
        do {
            let hurried = ExecutionContext(placement: .appExtension, remainingTime: 4, personIsPresent: true)
            let run = Run(
                group: group,
                agent: Agent(provider: script(), tools: [Echo()],
                             extensions: [Handover.afterOneTurn], execution: hurried),
                store: try FileEventStore(directory: directory)
            )
            for try await _ in run.start("what is it?") {}
        }

        // The app, later, with no hurry and no handover rule at all.
        let run = Run(
            group: group,
            agent: Agent(provider: script(), tools: [Echo()]),
            store: try FileEventStore(directory: directory)
        )
        #expect(try await run.state() == .handedOver("one turn is this process's share"))

        var events: [Event] = []
        for try await event in run.resume() { events.append(event) }
        #expect(events.last == .finished)
        #expect(try await run.state() == .finished)

        // One conversation, across two processes, in order.
        let messages = Message.projection(of: try await run.history())
        #expect(messages.first == .user("what is it?"))
        #expect(messages.last == .assistant(text: "All done.", toolCalls: []))
    }

    /// A rule may read how long the process has rather than count turns.
    @Test func aRuleMayReadHowLongIsLeft() async throws {
        let run = Run(
            agent: Agent(provider: script(), tools: [Echo()],
                         extensions: [Handover.whenTimeIsShort(reserve: 5)],
                         execution: ExecutionContext(placement: .background, remainingTime: 3,
                                                     personIsPresent: false)),
            store: InMemoryEventStore()
        )
        var events: [Event] = []
        for try await event in run.start("go") { events.append(event) }
        #expect(events.contains(.handedOver(by: "handover", reason: "only 3s of this process is left")))
    }

    /// With time in hand, nothing is handed over.
    @Test func withTimeInHandTheLoopJustRuns() async throws {
        let run = Run(
            agent: Agent(provider: script(), tools: [Echo()],
                         extensions: [Handover.whenTimeIsShort(reserve: 5)],
                         execution: ExecutionContext(placement: .foreground, remainingTime: 60)),
            store: InMemoryEventStore()
        )
        var events: [Event] = []
        for try await event in run.start("go") { events.append(event) }
        #expect(events.last == .finished)
        #expect(!events.contains { if case .handedOver = $0 { true } else { false } })
    }

    /// Recorded like everything else, and told apart from an ending.
    @Test func aHandoverSurvivesTheLogAndIsNotAnEnding() throws {
        let event = Event.handedOver(by: "handover", reason: "seconds left")
        let data = try JSONEncoder().encode(event)
        #expect(String(decoding: data, as: UTF8.self).contains("handed_over"))
        #expect(try JSONDecoder().decode(Event.self, from: data) == event)
        #expect(RunState(of: [.arrived(.person("hi")), .turnStarted(1), .turnEnded(.toolUse), event])
                == .handedOver("seconds left"))
    }
}

private struct Echo: Tool {
    let name = "echo", description = "Returns its arguments", access = ToolAccess.readOnly
    func execute(_ call: ToolCall, delivering: ResultDelivery) async throws -> ToolOutcome {
        .result(ToolResult(callID: call.id, content: call.arguments))
    }
}
