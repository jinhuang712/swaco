import Foundation
import Testing
import Swaco
import SwacoFoundationModels
import SwacoRuntime
import SwacoTesting

/// The on-device model is one provider among others. These checks are about
/// what it declares and how swaco behaves around it, not about the model's
/// output: a test must never need Apple Intelligence turned on, or a network.
@Suite struct TheOnDeviceModel {
    @Test func itDeclaresThatItRunsNoToolsForUs() {
        let model = OnDeviceModel()
        #expect(model.capabilities.tools == false)
        #expect(model.capabilities.providerExecutedTools == false)
    }

    /// Availability is a question the app can ask first, whatever the answer
    /// is on the machine running the tests.
    @Test func availabilityIsAnswerableBeforeAnyRequest() {
        switch OnDeviceModel().availability {
        case .ready, .downloading, .unavailable:
            break
        }
    }

    /// A request carrying tools is not refused and not trimmed. The mismatch
    /// is recorded, and the app decides what that means.
    @Test func toolsWithAModelThatHasNoneAreRecordedAsAMismatch() async throws {
        let store = InMemoryEventStore()
        let run = Run(
            agent: Agent(provider: ScriptedProvider.saying("Fine.").withoutTools(), tools: [Echo()]),
            store: store
        )
        var events: [Event] = []
        for try await event in run.start("go") { events.append(event) }

        #expect(events.contains(.capabilityMissing(.tools)))
        #expect(events.last == .finished, "the loop carries on: refusing is the app's to decide")
        // And the mismatch is in the log, so the app can act on it later too.
        #expect(try await run.history().contains(.capabilityMissing(.tools)))
    }

    @Test func aMismatchSurvivesTheLog() throws {
        let data = try JSONEncoder().encode(Event.capabilityMissing(.vision))
        #expect(String(decoding: data, as: UTF8.self).contains("capability_missing"))
        #expect(try JSONDecoder().decode(Event.self, from: data) == .capabilityMissing(.vision))
    }
}

private struct Echo: Tool {
    let name = "echo", description = "Returns its arguments", access = ToolAccess.readOnly
    func execute(_ call: ToolCall, delivering: ResultDelivery) async throws -> ToolOutcome {
        .result(ToolResult(callID: call.id, content: call.arguments))
    }
}
