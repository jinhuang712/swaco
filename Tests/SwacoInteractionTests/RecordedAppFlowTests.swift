import Foundation
import Testing
import Swaco
import SwacoInteraction
import SwacoRuntime
import SwacoTesting

/// The exact path the sample app takes when it runs on its recording. If this
/// passes and the app does not, the app is wrong; if it fails, swaco is.
@Suite struct TheSampleAppsRecordedConversation {
    @Test func theRecordedConversationRunsThroughTheDesk() async throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Examples/ChatApp/ChatApp/asking.jsonl")
        let model = try ScriptedProvider.replaying(file)
        let desk = Interaction()
        let run = Run(agent: Agent(provider: model, tools: desk.tools), store: InMemoryEventStore())

        var events: [Event] = []
        for try await event in run.start("Book me somewhere warm in February.") {
            events.append(event)
            if case .toolCallDeferred = event, let waiting = await desk.pending.first {
                switch waiting.request {
                case .question: await desk.answer(waiting.callID, with: "Quiet and secluded")
                case .confirmation: await desk.decide(waiting.callID, granted: true)
                }
            }
        }

        let said = Message.projection(of: events).map(\.text).joined(separator: " | ")
        #expect(events.last == .finished, "the recorded conversation must run to its end: \(said)")
        #expect(events.contains { if case .toolCallDeferred = $0 { true } else { false } },
                "the model asked, so the loop must have waited")
    }
}
