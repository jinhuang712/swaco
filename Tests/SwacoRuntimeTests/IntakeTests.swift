import Foundation
import Testing
import Swaco
import SwacoRuntime
import SwacoTesting

/// A provider that waits until it is told to answer, so a test can hand the
/// agent something while a turn is genuinely in flight.
private struct SlowProvider: Provider {
    let gate: Gate
    let script: [[StreamEvent]]

    func stream(_ request: ModelRequest) -> AsyncThrowingStream<StreamEvent, any Error> {
        let index = request.messages.filter { if case .assistant = $0 { true } else { false } }.count
        let turn = index < script.count ? script[index] : [.stop(.endTurn)]
        return AsyncThrowingStream { continuation in
            let task = Task {
                await gate.wait()
                for event in turn { continuation.yield(event) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Holds the first request open, and says when the loop has reached it,
    /// so a test can hand something in while a turn is genuinely in flight.
    actor Gate {
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

        /// Returns once the loop is inside a request.
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
}

@Suite struct SomethingArrivesMidLoop {
    /// Hands the agent something while the first turn is genuinely in flight,
    /// then lets the turn finish. Without the gate the loop would be over
    /// before the delivery, and the test would prove nothing.
    private func runDelivering(
        _ inbound: InboundEvent,
        extensions: [any Extension],
        second: String
    ) async throws -> (events: [Event], run: Run, inbox: Inbox) {
        let inbox = Inbox()
        let gate = SlowProvider.Gate()
        let agent = Agent(
            provider: SlowProvider(gate: gate, script: [
                [.text("First."), .stop(.endTurn)],
                [.text(second), .stop(.endTurn)],
            ]),
            tools: [],
            extensions: extensions,
            inbox: inbox
        )
        let run = Run(agent: agent, store: InMemoryEventStore())
        let collecting = Task {
            var events: [Event] = []
            for try await event in run.start("hello") { events.append(event) }
            return events
        }
        // Only once the request is genuinely out: an arrival that beats the
        // first request would join it, which proves something else.
        await gate.reached()
        await inbox.deliver(inbound)
        await gate.openUp()
        return (try await collecting.value, run, inbox)
    }

    /// The chat's rule: whatever arrives joins the conversation it arrived
    /// into, and the model sees it on the next turn.
    @Test func aRuleMayInjectItIntoTheNextTurn() async throws {
        let arrival = InboundEvent(source: .notification, text: "the parcel arrived")
        let (events, run, _) = try await runDelivering(
            arrival,
            extensions: [Intake.intoTheConversation],
            second: "And about that: yes."
        )

        #expect(events.contains(.arrived(arrival)))
        #expect(events.contains(.arrivalHandled(.inject, by: "intake")))
        #expect(events.contains(.text("And about that: yes.")),
                "an injected arrival must get the loop to take another turn")

        // And what arrived is in the model's context, saying where it came from.
        let messages = Message.projection(of: try await run.history())
        #expect(messages.contains(.user("[notification] the parcel arrived")))
        #expect(events.last == .finished)
    }

    /// With nobody holding an opinion, an arrival is not this loop's business
    /// and is left for whatever runs it.
    @Test func withNoIntakeExtensionAnArrivalIsLeft() async throws {
        let arrival = InboundEvent(source: .shortcut, text: "start the day")
        let (events, run, _) = try await runDelivering(
            arrival, extensions: [], second: "Should not happen."
        )

        #expect(events.contains(.arrivalHandled(.leave, by: "swaco")))
        #expect(!events.contains(.text("Should not happen.")))
        // The app is handed it back, and starts a run of its own for it.
        #expect(await run.left() == [arrival])
    }

    /// A rule may read what the loop was doing, not only where the event came
    /// from.
    @Test func aRuleReadsWhatTheLoopWasDoing() async throws {
        let seen = Situations()
        let (events, _, _) = try await runDelivering(
            .person("and one more thing"),
            extensions: [Intake { inbound, situation in
                seen.note(situation)
                return inbound.source == .person ? .inject : .leave
            }],
            second: "Second."
        )
        #expect(events.contains(.text("Second.")))
        #expect(seen.all.first?.turn == 1)
        #expect(seen.all.first?.waitingForResult == false)
    }

    /// Queued means after the work in hand, in the same loop.
    @Test func aQueuedArrivalIsAnsweredBeforeTheLoopEnds() async throws {
        let (events, run, _) = try await runDelivering(
            InboundEvent(source: .schedule, text: "the timer went off"),
            extensions: [Intake { _, _ in .queue }],
            second: "And the timer: noted."
        )
        #expect(events.contains(.arrivalHandled(.queue, by: "intake")))
        #expect(events.contains(.text("And the timer: noted.")))
        #expect(events.last == .finished)
        #expect(await run.left().isEmpty)
    }

    /// A rule reads facts and returns a decision, so it can be checked on its
    /// own without a loop at all.
    @Test func theShippedRulesSayWhatTheyMean() async {
        let moment = ExtensionContext(turn: 1, execution: .unknown)
        #expect(await Intake.intoTheConversation.arrived(.person("hi"), in: moment) == .inject)
        #expect(await Intake.intoTheConversation
            .arrived(InboundEvent(source: .sensor, text: "cold"), in: moment) == .inject)
        #expect(await Intake.peopleInterruptOthersDoNot.arrived(.person("hi"), in: moment) == .inject)
        #expect(await Intake.peopleInterruptOthersDoNot
            .arrived(InboundEvent(source: .sensor, text: "cold"), in: moment) == .leave)
    }

    /// Recorded like everything else, so a log explains why a loop went the
    /// way it did.
    @Test func handlingAnArrivalSurvivesTheLog() throws {
        for arrival in [Arrival.inject, .queue, .leave] {
            let event = Event.arrivalHandled(arrival, by: "intake")
            let data = try JSONEncoder().encode(event)
            #expect(try JSONDecoder().decode(Event.self, from: data) == event)
        }
    }

    private final class Situations: @unchecked Sendable {
        private let lock = NSLock()
        private var noted: [Intake.Situation] = []
        func note(_ situation: Intake.Situation) {
            lock.withLock { noted.append(situation) }
        }
        var all: [Intake.Situation] { lock.withLock { noted } }
    }
}
