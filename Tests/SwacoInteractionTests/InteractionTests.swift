import Foundation
import Testing
import Swaco
import SwacoInteraction
import SwacoRuntime
import SwacoTesting

private func asking(_ arguments: String, then answer: String, tool: String) -> ScriptedProvider {
    ScriptedProvider(turns: [
        [.toolCall(ToolCall(id: "r1", name: tool, arguments: arguments)), .stop(.toolUse)],
        [.text(answer), .stop(.endTurn)],
    ])
}

@Suite struct AskingAPerson {
    @Test func aQuestionWaitsForTheAnswerAndCarriesItBack() async throws {
        let desk = Interaction()
        let agent = Agent(
            provider: asking(#"{"question":"Which city?","options":["Paris","Rome"]}"#,
                             then: "Paris then.", tool: "ask"),
            tools: desk.tools
        )
        let run = Run(agent: agent, store: InMemoryEventStore())

        var events: [Event] = []
        for try await event in run.start("book me a trip") {
            events.append(event)
            if case .toolCallDeferred = event {
                // What the app does once it has shown the question.
                let waiting = try #require(await desk.pending.first)
                #expect(waiting.request == .question(Question(question: "Which city?",
                                                              options: ["Paris", "Rome"])))
                await desk.answer(waiting.callID, with: "Paris")
            }
        }

        #expect(events.contains(.toolResultArrived(ToolResult(callID: "r1", content: "Paris"))))
        #expect(events.last == .finished)
        #expect(await desk.pending.isEmpty)
    }

    @Test func aConfirmationCarriesTheDecision() async throws {
        let desk = Interaction()
        let agent = Agent(
            provider: asking(#"{"action":"Delete the file","detail":"It cannot be undone"}"#,
                             then: "Left alone.", tool: "confirm"),
            tools: desk.tools
        )
        let run = Run(agent: agent, store: InMemoryEventStore())

        var events: [Event] = []
        for try await event in run.start("tidy up") {
            events.append(event)
            if case .toolCallDeferred = event {
                let waiting = try #require(await desk.pending.first)
                #expect(waiting.request == .confirmation(
                    Confirmation(action: "Delete the file", detail: "It cannot be undone")))
                await desk.decide(waiting.callID, granted: false)
            }
        }
        #expect(events.contains(.toolResultArrived(ToolResult(callID: "r1", content: "refused"))))
    }

    /// A report does not wait, and does not end the reply.
    @Test func aReportDoesNotStopTheLoop() async throws {
        let desk = Interaction()
        let agent = Agent(
            provider: asking(#"{"message":"Halfway there"}"#, then: "All done.", tool: "report"),
            tools: desk.tools
        )
        let run = Run(agent: agent, store: InMemoryEventStore())

        let told = Task { await desk.reports.first { _ in true } }
        var events: [Event] = []
        for try await event in run.start("get on with it") { events.append(event) }

        #expect(await told.value == Report(message: "Halfway there"))
        #expect(!events.contains { if case .toolCallDeferred = $0 { true } else { false } })
        #expect(events.last == .finished)
    }

    /// Answering twice cannot happen, however many times a screen is shown.
    @Test func aSecondAnswerIsIgnored() async throws {
        let desk = Interaction()
        let agent = Agent(
            provider: asking(#"{"question":"Which city?"}"#, then: "Paris then.", tool: "ask"),
            tools: desk.tools
        )
        let run = Run(agent: agent, store: InMemoryEventStore())

        var results = 0
        for try await event in run.start("book me a trip") {
            if case .toolResultArrived = event { results += 1 }
            if case .toolCallDeferred = event {
                let id = try #require(await desk.pending.first?.callID)
                await desk.answer(id, with: "Paris")
                await desk.answer(id, with: "Rome")
            }
        }
        #expect(results == 1)
    }
}

@Suite struct AskingAcrossARelaunch {
    /// The exchange the phone makes hard: the agent asked, the person walked
    /// away, the process died, the app came back. The question is still
    /// waiting and the answer still reaches the loop that asked.
    @Test func aQuestionAsurvivesTheProcessThatAskedIt() async throws {
        let directory = URL.temporaryDirectory.appending(path: "swaco-ask-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let group = Run.newGroup()
        let script = { asking(#"{"question":"Which city?"}"#, then: "Paris then.", tool: "ask") }

        // Before: the agent asks, and the process goes away unanswered.
        do {
            let desk = Interaction()
            let run = Run(group: group,
                          agent: Agent(provider: script(), tools: desk.tools),
                          store: try FileEventStore(directory: directory))
            for try await event in run.start("book me a trip") {
                if case .toolCallDeferred = event { break }
            }
        }

        // After: a new desk, a new store, nothing kept in memory.
        let desk = Interaction()
        let store = try FileEventStore(directory: directory)
        let run = Run(group: group, agent: Agent(provider: script(), tools: desk.tools), store: store)
        #expect(try await run.state() == .awaitingResults([
            ToolCall(id: "r1", name: "ask", arguments: #"{"question":"Which city?"}"#),
        ]))

        var events: [Event] = []
        for try await event in run.resume() {
            events.append(event)
            if case .toolCallDeferred = event {
                // The app puts the question back on screen, from the desk.
                let waiting = try #require(await desk.pending.first)
                #expect(waiting.request == .question(Question(question: "Which city?", options: nil)))
                await desk.answer(waiting.callID, with: "Paris")
            }
        }

        #expect(events.contains(.toolResultArrived(ToolResult(callID: "r1", content: "Paris"))))
        #expect(events.last == .finished)
        #expect(try await run.state() == .finished)
    }
}

@Suite struct TellingSomebodySomethingOnTheWay {
    /// A report may carry a picture, which rides the way content rides
    /// everywhere else in swaco: bytes, or a reference to them.
    @Test func areportMayCarryMoreThanWords() async throws {
        let desk = Interaction()
        let reference = ContentReference(identifier: "chart-1", type: "image/png")
        let watching = Task { await desk.reports.first { _ in true } }

        await desk.tell(Report(message: "here is the chart", content: [.image(.reference(reference))]))
        let told = try #require(await watching.value)

        #expect(told.message == "here is the chart")
        #expect(told.content == [.image(.reference(reference))])
    }

    /// The model writes words. Pictures come from the app, which is the side
    /// that has them.
    @Test func themodelSaysWordsAndTheAppShowsWhatItHas() async throws {
        let desk = Interaction()
        let agent = Agent(
            provider: ScriptedProvider(turns: [
                [.toolCall(ToolCall(id: "r", name: "report",
                                    arguments: #"{"message":"halfway there"}"#)),
                 .stop(.toolUse)],
                [.text("Done."), .stop(.endTurn)],
            ]),
            tools: desk.tools
        )
        let watching = Task { await desk.reports.first { _ in true } }
        for try await _ in Run(agent: agent, store: InMemoryEventStore()).start("get on with it") {}

        let told = try #require(await watching.value)
        #expect(told.message == "halfway there")
        #expect(told.content.isEmpty, "a model has no picture to give")
    }

    @Test func areportSurvivesBeingWrittenDown() throws {
        let report = Report(message: "here it is", content: [.text("and this"), .image(
            .reference(ContentReference(identifier: "a", type: "image/png"))
        )])
        let data = try JSONEncoder().encode(report)
        #expect(try JSONDecoder().decode(Report.self, from: data) == report)
    }
}
