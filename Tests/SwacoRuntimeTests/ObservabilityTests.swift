import Foundation
import Testing
import Swaco
import SwacoRuntime
import SwacoTesting

@Suite struct WhatIsWrittenDown {
    /// The rule is structure yes, content no. A name that carries words would
    /// put them in the system log, where they must never be.
    @Test func anEventSaysItsKindAndNothingItCarries() {
        let secrets = [
            Event.arrived(.person("my address is 12 Mill Lane")),
            .text("your address is 12 Mill Lane"),
            .toolCallIssued(ToolCall(id: "c", name: "lookup", arguments: #"{"address":"12 Mill Lane"}"#)),
            .toolResultArrived(ToolResult(callID: "c", content: "12 Mill Lane, found")),
            .cancelled(.person, partial: "your address is 12 Mill"),
            .failed("could not reach 12 Mill Lane"),
            .refused(by: "approval", subject: .toolCall("c"), reason: "not for 12 Mill Lane"),
        ]
        for event in secrets {
            #expect(!event.kind.contains("Mill Lane"), "\(event.kind) carries content")
            #expect(!event.kind.contains("address"), "\(event.kind) carries content")
        }
    }

    /// And it still says enough to follow a run.
    @Test func aKindSaysEnoughToFollowARun() {
        #expect(Event.turnStarted(2).kind == "turn 2 started")
        #expect(Event.arrived(.person("hi")).kind == "arrived(person)")
        #expect(Event.toolCallIssued(ToolCall(id: "c", name: "weather", arguments: "{}")).kind
                == "call issued(weather)")
        #expect(Event.toolResultArrived(ToolResult(callID: "c", content: "x", isError: true)).kind
                == "result arrived(error)")
        #expect(Event.refused(by: "budget", subject: .turn(3), reason: "spent").kind == "refused(budget)")
    }
}

@Suite struct MeasuringARun {
    /// Trace is written through the public doors like any extension, and it
    /// changes nothing about what happens.
    @Test func tracingChangesNothingItMeasures() async throws {
        let script = ScriptedProvider(turns: [
            [.text("Checking."), .toolCall(ToolCall(id: "c", name: "echo", arguments: "{}")), .stop(.toolUse)],
            [.text("Done."), .stop(.endTurn)],
        ])
        func events(with extensions: [any Extension]) async throws -> [Event] {
            let run = Run(agent: Agent(provider: script, tools: [Echo()], extensions: extensions),
                          store: InMemoryEventStore())
            var events: [Event] = []
            for try await event in run.start("go") { events.append(event) }
            return events
        }
        let traced = try await events(with: [Trace()])
        let plain = try await events(with: [])
        #expect(traced == plain)
    }
}

@Suite struct WhatTheAppWasToProvide {
    /// An App Group that was never added is a clear error at the store, not a
    /// file error somewhere further down. Where the container comes from is a
    /// parameter, because the system answers differently on macOS and iOS and
    /// a test must not depend on which it is running on.
    @Test func anAppGroupThatIsNotThereSaysSo() {
        #expect(throws: StoreError.unreadable(
            "the App Group group.example.swaco is not on this app, so its container cannot be reached"
        )) {
            _ = try FileEventStore(appGroup: "group.example.swaco", container: { _ in nil })
        }
    }

    /// A group that is there gives a store under it, and no complaint.
    @Test func anAppGroupThatIsThereGivesAStore() async throws {
        let root = URL.temporaryDirectory.appending(path: "swaco-group-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try FileEventStore(appGroup: "group.example.swaco", container: { _ in root })
        try await store.append(.finished, to: "g")
        let directory = await store.directory
        #expect(directory.path().hasPrefix(root.path()))
        let met = Deployment.requirements(appGroup: "group.example.swaco", container: { _ in root })
        #expect(met.count == 1)
        #expect(met[0].isMet)
    }

    /// The check reports rather than guesses, and an app calls it itself.
    @Test func requirementsSayWhatIsNeededAndWhether() {
        let unmet = Deployment.requirements(appGroup: "group.example.swaco", container: { _ in nil })
        #expect(unmet.count == 1)
        #expect(unmet[0].module == "SwacoRuntime")
        #expect(unmet[0].isMet == false)
        #expect(unmet[0].what == "the App Group group.example.swaco")
        #expect(unmet[0].because.contains("share one log"))
        // Nothing is claimed about a module that needs nothing.
        #expect(Deployment.requirements().isEmpty)
    }
}

private struct Echo: Tool {
    let name = "echo", description = "Returns its arguments", access = ToolAccess.readOnly
    func execute(_ call: ToolCall, delivering: ResultDelivery) async throws -> ToolOutcome {
        .result(ToolResult(callID: call.id, content: call.arguments))
    }
}
