import Foundation
import Testing
import Swaco
import SwacoExtensions
import SwacoInteraction
import SwacoRuntime
import SwacoTesting

private struct Filing: Tool {
    let name = "file", description = "Files something away", access = ToolAccess.writing
    func execute(_ call: ToolCall, delivering: ResultDelivery) async throws -> ToolOutcome {
        .result(ToolResult(callID: call.id, content: "filed"))
    }
}

private struct Reading: Tool {
    let name = "read", description = "Reads something", access = ToolAccess.readOnly
    func execute(_ call: ToolCall, delivering: ResultDelivery) async throws -> ToolOutcome {
        .result(ToolResult(callID: call.id, content: "read"))
    }
}

private func callingBoth() -> ScriptedProvider {
    ScriptedProvider(turns: [
        [.toolCall(ToolCall(id: "r", name: "read", arguments: "{}")),
         .toolCall(ToolCall(id: "w", name: "file", arguments: "{}")),
         .stop(.toolUse)],
        [.text("Done."), .stop(.endTurn)],
    ])
}

@Suite struct TellingTheModelWhereItIs {
    @Test func theEnvironmentGoesInAheadOfTheFirstTurn() async throws {
        let seen = Recorder()
        let environment = EnvironmentContext(
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            locale: Locale(identifier: "en_GB"),
            timeZone: TimeZone(identifier: "Europe/Paris")!,
            device: "iPhone"
        )
        let run = Run(
            agent: Agent(provider: seen.watching(callingBoth()),
                         tools: [Reading(), Filing()],
                         extensions: [environment]),
            store: InMemoryEventStore()
        )
        var events: [Event] = []
        for try await event in run.start("what time is it?") { events.append(event) }

        let instructions = await seen.requests.first?.messages.first
        guard case .system(let text) = instructions else {
            Issue.record("the environment must arrive as instructions, not as a person's words")
            return
        }
        #expect(text.contains("Europe/Paris"))
        #expect(text.contains("en_GB"))
        #expect(text.contains("iPhone"))

        // And the rewrite says who did it.
        #expect(events.contains(.rewritten(by: "environment", subject: .request)))
        // Only once: the second turn is not told again.
        #expect(await seen.requests.count == 2)
        if case .system = await seen.requests[1].messages.first {
            #expect(await seen.requests[1].messages.filter { if case .system = $0 { true } else { false } }.count == 1)
        }
    }
}

@Suite struct HoldingCallsForApproval {
    /// The rule reads what the tool declared. Nothing else is held.
    @Test func onlyWhatTheRuleSelectsIsHeld() async throws {
        let asked = Asked()
        let tools: [any Tool] = [Reading(), Filing()]
        let approval = ToolApproval(
            tools: tools,
            rule: ToolApproval.anythingThatWrites,
            approve: { call in await asked.record(call); return false }
        )
        let run = Run(
            agent: Agent(provider: callingBoth(), tools: tools, extensions: [approval]),
            store: InMemoryEventStore()
        )
        var events: [Event] = []
        for try await event in run.start("tidy up") { events.append(event) }

        #expect(await asked.calls.map(\.name) == ["file"], "a read-only call must not be held")
        // The refused call still has a result, so the model is told.
        #expect(events.contains(.refused(by: "approval", subject: .toolCall("w"),
                                         reason: "the person did not approve file")))
        #expect(events.contains(.toolResultArrived(ToolResult(callID: "r", content: "read"))))
        #expect(events.contains(.toolResultArrived(
            ToolResult(callID: "w", content: "the person did not approve file", isError: true))))
        #expect(events.last == .finished, "one refused call does not end the conversation")
    }

    /// With no rule, nothing is held: swaco ships no policy of its own.
    @Test func withNoRuleNothingIsHeld() async throws {
        let asked = Asked()
        let tools: [any Tool] = [Reading(), Filing()]
        let approval = ToolApproval(tools: tools, approve: { call in await asked.record(call); return true })
        let run = Run(agent: Agent(provider: callingBoth(), tools: tools, extensions: [approval]),
                      store: InMemoryEventStore())
        for try await _ in run.start("tidy up") {}
        #expect(await asked.calls.isEmpty)
    }

    /// The whole point of approval: the app may route it through `confirm`,
    /// and swaco neither knows nor cares that it did.
    @Test func anAppMayRouteApprovalThroughConfirm() async throws {
        let desk = Interaction()
        let tools: [any Tool] = [Filing()]
        let approval = ToolApproval(
            tools: tools + desk.tools,
            rule: ToolApproval.anythingThatWrites,
            approve: { call in
                // What an app writes: ask through confirm, wait, read the answer.
                await desk.ask(.init(action: "File it?", detail: call.name)) == true
            }
        )
        let run = Run(agent: Agent(provider: callingBoth(), tools: tools + desk.tools, extensions: [approval]),
                      store: InMemoryEventStore())

        let answering = Task {
            while true {
                if let waiting = await desk.pending.first {
                    await desk.decide(waiting.callID, granted: true)
                    return
                }
                await Task.yield()
            }
        }
        var events: [Event] = []
        for try await event in run.start("tidy up") { events.append(event) }
        _ = await answering.value

        #expect(events.contains(.toolResultArrived(ToolResult(callID: "w", content: "filed"))))
        #expect(!events.contains { if case .refused = $0 { true } else { false } })
    }
}

@Suite struct TryingAgain {
    @Test func aTransientFailureIsTriedAgainAndSucceeds() async throws {
        let flaky = FailingOnce(then: ScriptedProvider.saying("Second time lucky."))
        let run = Run(
            agent: Agent(provider: flaky, tools: [],
                         extensions: [Retry(limit: 3, first: .milliseconds(1))]),
            store: InMemoryEventStore()
        )
        var events: [Event] = []
        for try await event in run.start("hello") { events.append(event) }

        #expect(events.contains(.text("Second time lucky.")))
        #expect(events.last == .finished)
        // A retried request is not a failure, so the log does not claim one.
        #expect(!events.contains { if case .failed = $0 { true } else { false } })
    }

    @Test func aFailureWorthNoRetryEndsTheLoopWithItsReason() async throws {
        let broken = FailingOnce(then: ScriptedProvider.saying("never reached"),
                                 error: URLError(.badServerResponse), forever: true)
        let run = Run(agent: Agent(provider: broken, tools: [], extensions: [Retry()]),
                      store: InMemoryEventStore())
        var events: [Event] = []
        for try await event in run.start("hello") { events.append(event) }
        #expect(events.contains { if case .failed = $0 { true } else { false } })
    }
}

// MARK: - Small helpers

private actor Recorder {
    private(set) var requests: [ModelRequest] = []
    nonisolated func watching(_ provider: ScriptedProvider) -> WatchingProvider { WatchingProvider(provider, self) }
    fileprivate func note(_ request: ModelRequest) { requests.append(request) }
}

private struct WatchingProvider: Provider {
    let wrapped: ScriptedProvider
    let recorder: Recorder
    init(_ wrapped: ScriptedProvider, _ recorder: Recorder) {
        self.wrapped = wrapped
        self.recorder = recorder
    }
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<StreamEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                await recorder.note(request)
                do {
                    for try await event in wrapped.stream(request) { continuation.yield(event) }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private actor Asked {
    private(set) var calls: [ToolCall] = []
    func record(_ call: ToolCall) { calls.append(call) }
}

/// Fails the first request, then plays a script. The failure a retry is for.
private struct FailingOnce: Provider {
    let then: ScriptedProvider
    let error: any Error
    let forever: Bool
    private let attempts = Attempts()

    init(then: ScriptedProvider, error: any Error = URLError(.networkConnectionLost), forever: Bool = false) {
        self.then = then
        self.error = error
        self.forever = forever
    }

    func stream(_ request: ModelRequest) -> AsyncThrowingStream<StreamEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let isFirst = await attempts.first()
                if forever || isFirst {
                    continuation.finish(throwing: error)
                    return
                }
                do {
                    for try await event in then.stream(request) { continuation.yield(event) }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private actor Attempts {
        private var count = 0
        func first() -> Bool {
            count += 1
            return count == 1
        }
    }
}
