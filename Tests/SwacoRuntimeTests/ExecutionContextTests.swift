import Foundation
import Testing
import Swaco
import SwacoRuntime
import SwacoTesting

@Suite struct KnowingWhereWeAreRunning {
    /// The system is asked, and whatever it says is a usable answer. What it
    /// says differs between a Mac, a simulator and a phone, so the check is
    /// that an answer comes back rather than which one.
    @Test @MainActor func thesystemIsAskedAndAnswers() {
        let context = WhereWeAreRunning.now()
        switch context.placement {
        case .foreground, .background, .appExtension: break
        }
        // Nothing said is not the same as plenty, so nil stays nil.
        if let remaining = context.remainingTime {
            #expect(remaining >= 0)
        }
    }

    /// What only the caller can know is passed in, and it wins.
    @Test @MainActor func whatOnlyTheCallerKnowsIsTaken() {
        let context = WhereWeAreRunning.now(remainingTime: 7)
        #expect(context.remainingTime == 7)
    }

    /// The point of any of this: a rule written over these facts changes what
    /// a loop does.
    @Test func afactFromTheSystemReachesTheRuleThatReadsIt() async throws {
        let script = ScriptedProvider(turns: [
            [.text("one"), .toolCall(ToolCall(id: "c", name: "echo", arguments: "{}")), .stop(.toolUse)],
            [.text("two"), .stop(.endTurn)],
        ])
        // A process with seconds left hands over; the same agent with time in
        // hand does not.
        let hurried = Agent(provider: script, tools: [Echo()],
                            extensions: [Handover.whenTimeIsShort(reserve: 5)])
            .running(in: ExecutionContext(placement: .appExtension, remainingTime: 3,
                                          personIsPresent: false))
        let unhurried = hurried.running(in: ExecutionContext(placement: .foreground,
                                                            remainingTime: 600))

        var stopped: [Event] = []
        for try await event in Run(agent: hurried, store: InMemoryEventStore()).start("go") {
            stopped.append(event)
        }
        var carriedOn: [Event] = []
        for try await event in Run(agent: unhurried, store: InMemoryEventStore()).start("go") {
            carriedOn.append(event)
        }

        #expect(stopped.contains { if case .handedOver = $0 { true } else { false } })
        #expect(carriedOn.last == .finished)
        #expect(!carriedOn.contains { if case .handedOver = $0 { true } else { false } })
    }

    /// An agent keeps everything else when it is told where it is.
    @Test func tellingAnAgentWhereItIsChangesOnlyThat() {
        let agent = Agent(provider: ScriptedProvider.saying("hi"), tools: [Echo()],
                          extensions: [Handover.afterOneTurn])
        let told = agent.running(in: ExecutionContext(placement: .background, remainingTime: 20))
        #expect(told.tools.count == agent.tools.count)
        #expect(told.extensions.count == agent.extensions.count)
        #expect(told.execution.placement == .background)
        #expect(agent.execution.placement == .foreground, "the original is untouched")
    }
}

private struct Echo: Tool {
    let name = "echo", description = "Returns its arguments", access = ToolAccess.readOnly
    func execute(_ call: ToolCall, delivering: ResultDelivery) async throws -> ToolOutcome {
        .result(ToolResult(callID: call.id, content: call.arguments))
    }
}
