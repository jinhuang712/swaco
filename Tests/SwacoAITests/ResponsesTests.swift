import Foundation
import Testing
import Swaco
import SwacoAI
import SwacoOpenAI
import SwacoTesting

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
        // Text, the call, what it cost, and the stop. Reasoning and the
        // vendor's bookkeeping are carried by no swaco event.
        #expect(events.count == text.count + 3)
        #expect(events.contains { if case .usage = $0 { true } else { false } })
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
    @Test func toolSchemaPassesThroughAsJSON() async throws {
        let tool = Weather()
        let request = ModelRequest(
            messages: [.user("hello")],
            tools: [ToolDefinition(name: tool.name, description: tool.description, parameters: tool.parameters)]
        )
        let body = try await encodedBody(for: request)
        let tools = try #require(body["tools"] as? [[String: Any]])
        let schema = try #require(tools.first?["parameters"] as? [String: Any])
        #expect(schema["type"] as? String == "object")
        #expect((schema["required"] as? [String]) == ["city"])
        #expect(((schema["properties"] as? [String: Any])?["city"] as? [String: Any])?["type"] as? String == "string")
    }

    /// Ids are preserved, so a result returns to the call that asked for it.
    @Test func callsAndResultsKeepTheirIdentity() async throws {
        let call = ToolCall(id: "call_7", name: "weather", arguments: #"{"city":"Paris"}"#)
        let request = ModelRequest(
            messages: [
                .user("weather?"),
                .assistant(text: "Checking.", toolCalls: [call]),
                .toolResult(ToolResult(callID: "call_7", content: "18C")),
            ],
            tools: []
        )
        let body = try await encodedBody(for: request)
        let items = try #require(body["input"] as? [[String: Any]])
        #expect(items.count == 4)
        #expect(items[1]["role"] as? String == "assistant")
        #expect(items[2]["type"] as? String == "function_call")
        #expect(items[2]["call_id"] as? String == "call_7")
        #expect(items[3]["type"] as? String == "function_call_output")
        #expect(items[3]["call_id"] as? String == "call_7")
        #expect(items[3]["output"] as? String == "18C")
    }

    /// An assistant turn that was only a tool call carries no empty message.
    @Test func emptyAssistantTextIsNotSent() async throws {
        let request = ModelRequest(
            messages: [.assistant(text: "", toolCalls: [ToolCall(id: "c", name: "n", arguments: "{}")])],
            tools: []
        )
        let body = try await encodedBody(for: request)
        let items = try #require(body["input"] as? [[String: Any]])
        #expect(items.count == 1)
        #expect(items[0]["type"] as? String == "function_call")
    }

    /// The body a provider would send, without sending it.
    private func encodedBody(for request: ModelRequest) async throws -> [String: Any] {
        let provider = OpenAI.compatible(
            model: "muse-spark-1.3-contributor",
            endpoint: "https://example.invalid/v1/responses",
            authentication: .bearer("not-used"),
            headers: ["x-opencode-session": "test"]
        )
        let data = try await provider.encodedRequestForTesting(request)
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

@Suite struct SendingPictures {
    private let pixel = Data([0x89, 0x50, 0x4E, 0x47])

    /// Bytes go on the wire as the vendor wants them, in the same message as
    /// the words they came with.
    @Test func bytesBecomeADataURLBesideTheWords() async throws {
        let request = ModelRequest(
            messages: [.user([.text("what is this?"), .image(.bytes(pixel, type: "image/png"))])],
            tools: []
        )
        let items = try #require(try await body(for: request)["input"] as? [[String: Any]])
        let parts = try #require(items.first?["content"] as? [[String: Any]])
        #expect(parts.count == 2)
        #expect(parts[0]["type"] as? String == "input_text")
        #expect(parts[1]["type"] as? String == "input_image")
        #expect(parts[1]["image_url"] as? String == "data:image/png;base64,\(pixel.base64EncodedString())")
    }

    /// A part that points at bytes is resolved through the store the request
    /// names. The provider fetches; it holds no store of its own.
    @Test func aReferenceIsFetchedThroughTheStoreTheRequestNames() async throws {
        let store = Bytes(pixel)
        let reference = ContentReference(identifier: "one", type: "image/png")
        let request = ModelRequest(
            messages: [.user([.image(.reference(reference))])],
            tools: [],
            content: store
        )
        let items = try #require(try await body(for: request)["input"] as? [[String: Any]])
        let parts = try #require(items.first?["content"] as? [[String: Any]])
        #expect(parts[0]["image_url"] as? String == "data:image/png;base64,\(pixel.base64EncodedString())")
        #expect(await store.loads == 1, "the bytes are read once, when the request is built")
    }

    /// Reasoning is the model's own. It is not sent back to it.
    @Test func reasoningIsNotSentBack() async throws {
        let request = ModelRequest(
            messages: [.assistant(content: [.reasoning("thinking"), .text("done")], toolCalls: [])],
            tools: []
        )
        let items = try #require(try await body(for: request)["input"] as? [[String: Any]])
        let parts = try #require(items.first?["content"] as? [[String: Any]])
        #expect(parts.count == 1)
        #expect(parts[0]["text"] as? String == "done")
    }

    private func body(for request: ModelRequest) async throws -> [String: Any] {
        let provider = OpenAI.compatible(
            model: "any", endpoint: "https://example.invalid/v1/responses",
            authentication: .bearer("not-used")
        )
        let data = try await provider.encodedRequestForTesting(request)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private actor Bytes: ContentStore {
        private let data: Data
        private(set) var loads = 0
        init(_ data: Data) { self.data = data }
        func store(_ data: Data, type: String) async throws -> ContentReference {
            ContentReference(identifier: "one", type: type)
        }
        func load(_ reference: ContentReference) async throws -> Data {
            loads += 1
            return data
        }
        func remove(_ reference: ContentReference) async throws {}
    }
}

@Suite struct WhatATurnCost {
    /// The vendor's counts arrive as swaco's, from the recorded exchange.
    @Test func usageIsNormalisedFromTheRecording() throws {
        var mapper = ResponsesEventMapper()
        var events: [StreamEvent] = []
        for recorded in try recordedEvents("muse-spark-1.3-tool-call") {
            events += try mapper.map(recorded)
        }
        let usage = events.compactMap { if case .usage(let usage) = $0 { usage } else { nil } }
        let spent = try #require(usage.first)
        #expect(spent.inputTokens > 0)
        #expect(spent.outputTokens > 0)
        #expect(spent.reasoningTokens > 0, "the model reasoned, and the count says so")
        #expect(spent.totalTokens == spent.inputTokens + spent.outputTokens)
        // Counted once per turn, and before the stop.
        #expect(usage.count == 1)
        #expect(events.last == .stop(.toolUse))
    }
}

@Suite struct ReplayingARealExchange {
    /// The workflow the feature list promises, end to end: this exchange
    /// happened once against a hosted model, and every run of it since has
    /// been a file. No key, no network, and the same events.
    @Test func arealExchangeReplaysWithoutAKeyOrANetwork() async throws {
        let file = try #require(Bundle.module.url(
            forResource: "Fixtures/muse-spark-1.3-weather", withExtension: "jsonl"
        ))
        let model = try ScriptedProvider.replaying(file)

        var events: [StreamEvent] = []
        // Turn one: the model says something and asks for the tool.
        for try await event in model.stream(ModelRequest(messages: [.user("Weather in Paris?")], tools: [])) {
            events.append(event)
        }
        #expect(events.contains { if case .toolCall(let call) = $0 { call.name == "weather" } else { false } })
        #expect(events.contains { if case .usage(let usage) = $0 { usage.totalTokens > 0 } else { false } })
        #expect(events.last == .stop(.toolUse))

        // Turn two: with the result in the context, it answers.
        var second: [StreamEvent] = []
        for try await event in model.stream(ModelRequest(
            messages: [
                .user("Weather in Paris?"),
                .assistant(text: "Checking.", toolCalls: [ToolCall(id: "c", name: "weather", arguments: "{}")]),
                .toolResult(ToolResult(callID: "c", content: "18C and sunny")),
            ],
            tools: []
        )) { second.append(event) }
        let said = second.compactMap { if case .text(let piece) = $0 { piece } else { nil } }.joined()
        #expect(said.contains("18"), "the recorded reply used what the tool returned")
        #expect(second.last == .stop(.endTurn))
    }
}

@Suite struct KeepingTokens {
    /// The dull part swaco does: attach the token, notice it is stale,
    /// exchange it, keep the new one.
    @Test func astaleTokenIsExchangedBeforeTheRequest() async throws {
        let store = InMemoryTokenStore(Tokens(
            access: "old", refresh: "renew", expires: Date().addingTimeInterval(10)
        ))
        let exchanges = Exchanges()
        let authentication = Authentication.oauth(store: store) { refresh in
            await exchanges.note(refresh)
            return Tokens(access: "new", refresh: "renew-again",
                          expires: Date().addingTimeInterval(3600))
        }

        var request = URLRequest(url: URL(string: "https://example.invalid")!)
        try await authentication.authenticate(&request)

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer new")
        #expect(await exchanges.all == ["renew"])
        // And the new pair is the one kept, so the next request does not
        // exchange again.
        #expect(try await store.tokens()?.access == "new")
        try await authentication.authenticate(&request)
        #expect(await exchanges.all.count == 1)
    }

    /// A token with life in it is used as it is.
    @Test func afreshTokenIsUsedAsItIs() async throws {
        let store = InMemoryTokenStore(Tokens(
            access: "good", refresh: "renew", expires: Date().addingTimeInterval(3600)
        ))
        let exchanges = Exchanges()
        let authentication = Authentication.oauth(store: store) { refresh in
            await exchanges.note(refresh)
            return Tokens(access: "unexpected")
        }
        var request = URLRequest(url: URL(string: "https://example.invalid")!)
        try await authentication.authenticate(&request)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer good")
        #expect(await exchanges.all.isEmpty)
    }

    /// Nobody has signed in yet, which is an error the app can act on rather
    /// than a request that fails at the vendor. Signing in is the app's flow.
    @Test func withNoTokensTheAppIsToldBeforeTheRequest() async {
        let authentication = Authentication.oauth(store: InMemoryTokenStore()) { _ in
            Tokens(access: "never")
        }
        var request = URLRequest(url: URL(string: "https://example.invalid")!)
        await #expect(throws: AuthenticationError.noTokens) {
            try await authentication.authenticate(&request)
        }
    }

    /// Staleness is about the next request, not the last one: a token that
    /// expires in flight fails the request it was attached to.
    @Test func atokenAboutToExpireCountsAsStale() {
        let now = Date()
        #expect(Tokens(access: "a", expires: now.addingTimeInterval(30)).isStale(now: now))
        #expect(!Tokens(access: "a", expires: now.addingTimeInterval(300)).isStale(now: now))
        // A token with no expiry says nothing, so nothing is assumed.
        #expect(!Tokens(access: "a").isStale(now: now))
    }

    @Test func tokensSurviveBeingWrittenDown() throws {
        let tokens = Tokens(access: "a", refresh: "b", expires: Date(timeIntervalSince1970: 1))
        let data = try JSONEncoder().encode(tokens)
        #expect(try JSONDecoder().decode(Tokens.self, from: data) == tokens)
    }

    private actor Exchanges {
        private(set) var all: [String] = []
        func note(_ refresh: String) { all.append(refresh) }
    }
}
