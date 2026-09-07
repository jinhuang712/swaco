import Foundation
import Testing
import Swaco
import SwacoAI
import SwacoOpenAI

/// The recorded exchange every test here replays. Run once against the real
/// model, kept as a fixture, replayed thereafter: no key, no network.
private func recordedEvents(_ name: String) throws -> [ServerSentEvent] {
    let url = try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "sse"))
    var parser = ServerSentEventParser()
    var events: [ServerSentEvent] = []
    for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false) {
        if let event = parser.consume(String(line)) { events.append(event) }
    }
    if let last = parser.finish() { events.append(last) }
    return events
}

@Suite struct ServerSentEventParsing {
    /// The blank line is the separator, so it must survive being read. The
    /// mistake this guards against is `AsyncLineSequence`, which drops it and
    /// turns a whole stream into one event.
    @Test func blankLineSeparatesEvents() {
        var parser = ServerSentEventParser()
        #expect(parser.consume("event: a") == nil)
        #expect(parser.consume("data: one") == nil)
        #expect(parser.consume("") == ServerSentEvent(type: "a", data: "one"))
        #expect(parser.consume("data: two") == nil)
        #expect(parser.consume("") == ServerSentEvent(type: nil, data: "two"))
    }

    @Test func carriageReturnsAndCommentsAreIgnored() {
        var parser = ServerSentEventParser()
        #expect(parser.consume(": a comment") == nil)
        #expect(parser.consume("data: value\r") == nil)
        #expect(parser.consume("\r") == ServerSentEvent(type: nil, data: "value"))
    }

    @Test func dataLinesJoin() {
        var parser = ServerSentEventParser()
        _ = parser.consume("data: one")
        _ = parser.consume("data: two")
        #expect(parser.consume("") == ServerSentEvent(type: nil, data: "one\ntwo"))
    }
}

@Suite struct RecordedResponsesStream {
    @Test func mapsToTextThenToolCallThenStop() throws {
        var mapper = ResponsesEventMapper()
        var events: [StreamEvent] = []
        for recorded in try recordedEvents("muse-spark-1.3-tool-call") {
            events += try mapper.map(recorded)
        }

        let text = events.compactMap { if case .text(let piece) = $0 { piece } else { nil } }
        #expect(!text.isEmpty)
        #expect(text.joined().contains("Paris"))

        let calls = events.compactMap { if case .toolCall(let call) = $0 { call } else { nil } }
        #expect(calls.count == 1)
        #expect(calls.first?.name == "weather")
        #expect(calls.first?.id.hasPrefix("call_") == true)
        #expect(calls.first?.arguments == #"{"city":"Paris"}"#)

        // A turn that asked for a tool stops for tool use, not end of turn.
        #expect(events.last == .stop(.toolUse))
        // Reasoning and bookkeeping events are carried by no swaco event.
        #expect(events.count == text.count + 2)
    }

    @Test func vendorErrorsBecomeProviderErrors() {
        var mapper = ResponsesEventMapper()
        let event = ServerSentEvent(
            type: "error",
            data: #"{"type":"error","error":{"type":"MissingSessionID","message":"cannot be routed"}}"#
        )
        #expect(throws: ProviderError.vendor(type: "MissingSessionID", message: "cannot be routed")) {
            try mapper.map(event)
        }
    }

    @Test func truncationStopsForLength() throws {
        var mapper = ResponsesEventMapper()
        let event = ServerSentEvent(
            type: "response.completed",
            data: #"{"type":"response.completed","response":{"incomplete_details":{"reason":"max_output_tokens"}}}"#
        )
        #expect(try mapper.map(event) == [.stop(.maxTokens)])
    }
}

@Suite struct ResponsesRequestEncoding {
    private struct Weather: Tool {
        let name = "weather", description = "Weather for a city", access = ToolAccess.readOnly
        let parameters = #"{"type":"object","properties":{"city":{"type":"string"}},"required":["city"]}"#
        func execute(_ call: ToolCall, delivering: ResultDelivery) async throws -> ToolOutcome {
            .result(ToolResult(callID: call.id, content: "18C"))
        }
    }

    /// A tool's schema is JSON the app wrote. It reaches the vendor as JSON,
    /// not as a string, and unchanged.
    @Test func toolSchemaPassesThroughAsJSON() throws {
        let tool = Weather()
        let request = ModelRequest(
            messages: [.user("hello")],
            tools: [ToolDefinition(name: tool.name, description: tool.description, parameters: tool.parameters)]
        )
        let body = try encodedBody(for: request)
        let tools = try #require(body["tools"] as? [[String: Any]])
        let schema = try #require(tools.first?["parameters"] as? [String: Any])
        #expect(schema["type"] as? String == "object")
        #expect((schema["required"] as? [String]) == ["city"])
        #expect(((schema["properties"] as? [String: Any])?["city"] as? [String: Any])?["type"] as? String == "string")
    }

    /// Ids are preserved, so a result returns to the call that asked for it.
    @Test func callsAndResultsKeepTheirIdentity() throws {
        let call = ToolCall(id: "call_7", name: "weather", arguments: #"{"city":"Paris"}"#)
        let request = ModelRequest(
            messages: [
                .user("weather?"),
                .assistant(text: "Checking.", toolCalls: [call]),
                .toolResult(ToolResult(callID: "call_7", content: "18C")),
            ],
            tools: []
        )
        let items = try #require(try encodedBody(for: request)["input"] as? [[String: Any]])
        #expect(items.count == 4)
        #expect(items[1]["role"] as? String == "assistant")
        #expect(items[2]["type"] as? String == "function_call")
        #expect(items[2]["call_id"] as? String == "call_7")
        #expect(items[3]["type"] as? String == "function_call_output")
        #expect(items[3]["call_id"] as? String == "call_7")
        #expect(items[3]["output"] as? String == "18C")
    }

    /// An assistant turn that was only a tool call carries no empty message.
    @Test func emptyAssistantTextIsNotSent() throws {
        let request = ModelRequest(
            messages: [.assistant(text: "", toolCalls: [ToolCall(id: "c", name: "n", arguments: "{}")])],
            tools: []
        )
        let items = try #require(try encodedBody(for: request)["input"] as? [[String: Any]])
        #expect(items.count == 1)
        #expect(items[0]["type"] as? String == "function_call")
    }

    /// The body a provider would send, without sending it.
    private func encodedBody(for request: ModelRequest) throws -> [String: Any] {
        let provider = OpenAI.compatible(
            model: "muse-spark-1.3-contributor",
            endpoint: "https://example.invalid/v1/responses",
            authentication: .bearer("not-used"),
            headers: ["x-opencode-session": "test"]
        )
        let data = try provider.encodedRequestForTesting(request)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

@Suite struct Authenticating {
    @Test func bearerTokenGoesInTheHeader() async throws {
        var request = URLRequest(url: URL(string: "https://example.invalid")!)
        try await Authentication.bearer("abc").authenticate(&request)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
    }

    @Test func apiKeyGoesInTheHeaderTheVendorNames() async throws {
        var request = URLRequest(url: URL(string: "https://example.invalid")!)
        try await Authentication.apiKey("abc", header: "x-api-key").authenticate(&request)
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "abc")
    }

    /// A missing key is an error before the request, not a failure after it.
    @Test func aMissingEnvironmentVariableIsAnError() async {
        var request = URLRequest(url: URL(string: "https://example.invalid")!)
        await #expect(throws: AuthenticationError.missingEnvironmentVariable("SWACO_ABSENT_KEY")) {
            try await Authentication.bearer(environment: "SWACO_ABSENT_KEY").authenticate(&request)
        }
    }
}
