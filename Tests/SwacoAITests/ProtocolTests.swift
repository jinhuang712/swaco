import Foundation
import Testing
import Swaco
import SwacoAI
import SwacoAnthropic
import SwacoOpenAI
import SwacoTesting

/// Three protocols, one vocabulary. What differs is absorbed at the edge, and
/// these are the checks that say so.
@Suite struct EveryProtocolSpeaksTheSameVocabulary {
    /// Each of the three, replayed from something a vendor really said,
    /// reaches the same shape of events.
    @Test(arguments: [
        "muse-spark-1.3-weather", "deepseek-v4-flash-weather", "minimax-m3-weather",
    ])
    func arecordedExchangeReachesTheSameEvents(_ recording: String) async throws {
        let file = try #require(Bundle.module.url(
            forResource: "Fixtures/\(recording)", withExtension: "jsonl"
        ))
        let model = try ScriptedProvider.replaying(file)

        var first: [StreamEvent] = []
        for try await event in model.stream(ModelRequest(messages: [.user("weather?")], tools: [])) {
            first.append(event)
        }
        let calls = first.compactMap { if case .toolCall(let call) = $0 { call } else { nil } }
        #expect(calls.count == 1, "every one of them asked for the tool")
        #expect(calls[0].name == "weather")
        // Whatever the vendor's spelling, the arguments arrive as one JSON
        // object with the city in it.
        let arguments = try #require(
            try JSONSerialization.jsonObject(with: Data(calls[0].arguments.utf8)) as? [String: Any]
        )
        #expect(arguments["city"] as? String == "Paris")
        #expect(first.last == .stop(.toolUse))
        #expect(first.contains { if case .usage(let usage) = $0 { usage.totalTokens > 0 } else { false } })

        var second: [StreamEvent] = []
        for try await event in model.stream(ModelRequest(
            messages: [
                .user("weather?"),
                .assistant(text: "Checking.", toolCalls: [calls[0]]),
                .toolResult(ToolResult(callID: calls[0].id, content: "18C and sunny")),
            ],
            tools: []
        )) { second.append(event) }
        let said = second.compactMap { if case .text(let piece) = $0 { piece } else { nil } }.joined()
        #expect(said.contains("18"), "each of them used what the tool returned")
        #expect(second.last == .stop(.endTurn))
    }
}

@Suite struct AssemblingWhatArrivesInPieces {
    /// The work the older protocol needs and the newer one does not: a call
    /// spelled out a fragment at a time, sometimes a single brace, and handed
    /// over whole only when the turn ends.
    @Test func atoolCallSpelledOutInFragmentsArrivesWhole() throws {
        var mapper = ChatCompletionsEventMapper()
        var events: [StreamEvent] = []
        let fragments = [
            #"{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"weather","arguments":""}}]}}]}"#,
            #"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\""}}]}}]}"#,
            #"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"city"}}]}}]}"#,
            #"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\": \""}}]}}]}"#,
            #"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"Paris\"}"}}]}}]}"#,
            #"{"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#,
        ]
        for fragment in fragments {
            events += try mapper.map(ServerSentEvent(type: nil, data: fragment))
        }
        // The stop waits for the end of the stream, so every protocol says
        // what a turn cost before it says the turn is over.
        events += mapper.done()
        #expect(events == [
            .toolCall(ToolCall(id: "call_1", name: "weather", arguments: #"{"city": "Paris"}"#)),
            .stop(.toolUse),
        ], "nothing may be handed over until the whole of it has arrived")
    }

    /// Two calls at once keep their own fragments apart.
    @Test func twoCallsAtOnceDoNotRunTogether() throws {
        var mapper = ChatCompletionsEventMapper()
        var events: [StreamEvent] = []
        for fragment in [
            #"{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"a","function":{"name":"one","arguments":"{\"x\":1"}}]}}]}"#,
            #"{"choices":[{"delta":{"tool_calls":[{"index":1,"id":"b","function":{"name":"two","arguments":"{\"y\":2"}}]}}]}"#,
            #"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"}"}}]}}]}"#,
            #"{"choices":[{"delta":{"tool_calls":[{"index":1,"function":{"arguments":"}"}}]}}]}"#,
            #"{"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#,
        ] {
            events += try mapper.map(ServerSentEvent(type: nil, data: fragment))
        }
        events += mapper.done()
        #expect(events == [
            .toolCall(ToolCall(id: "a", name: "one", arguments: #"{"x":1}"#)),
            .toolCall(ToolCall(id: "b", name: "two", arguments: #"{"y":2}"#)),
            .stop(.toolUse),
        ])
    }

    /// A vendor that streams its thinking beside its answer is carried, not
    /// dropped and not mistaken for the answer.
    @Test func thinkingIsCarriedApartFromTheAnswer() throws {
        var mapper = ChatCompletionsEventMapper()
        var events: [StreamEvent] = []
        for chunk in [
            #"{"choices":[{"delta":{"reasoning_content":"the user wants"}}]}"#,
            #"{"choices":[{"delta":{"content":"18C."}}]}"#,
            #"{"choices":[{"delta":{},"finish_reason":"stop"}]}"#,
        ] {
            events += try mapper.map(ServerSentEvent(type: nil, data: chunk))
        }
        events += mapper.done()
        #expect(events == [.reasoning("the user wants"), .text("18C."), .stop(.endTurn)])
    }
}

@Suite struct TheMessagesProtocolOnTheWire {
    /// Instructions are a field of their own here, not a message, and a tool's
    /// answer is a block of a person's message rather than a role.
    @Test func instructionsAndToolResultsGoWhereThisProtocolPutsThem() async throws {
        let provider = Anthropic.compatible(
            model: "any", endpoint: "https://example.invalid/v1/messages",
            authentication: .apiKey("not-used", header: Anthropic.keyHeader)
        )
        let call = ToolCall(id: "c1", name: "weather", arguments: #"{"city":"Paris"}"#)
        let data = try await provider.encodedRequestForTesting(ModelRequest(
            messages: [
                .system("Be brief."),
                .user("weather?"),
                .assistant(text: "Checking.", toolCalls: [call]),
                .toolResult(ToolResult(callID: "c1", content: "18C")),
            ],
            tools: [ToolDefinition(name: "weather", description: "Weather",
                                   parameters: #"{"type":"object"}"#)]
        ))
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(body["system"] as? String == "Be brief.")
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.count == 3)
        #expect(messages[0]["role"] as? String == "user")
        #expect(messages[1]["role"] as? String == "assistant")
        // The answer to a call comes back as the person's turn, which is this
        // protocol's way.
        #expect(messages[2]["role"] as? String == "user")
        let blocks = try #require(messages[2]["content"] as? [[String: Any]])
        #expect(blocks[0]["type"] as? String == "tool_result")
        #expect(blocks[0]["tool_use_id"] as? String == "c1")
        // A tool's schema is JSON, under this protocol's name for it.
        let tools = try #require(body["tools"] as? [[String: Any]])
        #expect(tools[0]["input_schema"] != nil)
    }

    /// This protocol will not take two messages of one role in a row, so two
    /// results become one turn.
    @Test func twoResultsInARowBecomeOneTurn() async throws {
        let provider = Anthropic.compatible(
            model: "any", endpoint: "https://example.invalid/v1/messages",
            authentication: .apiKey("k", header: Anthropic.keyHeader)
        )
        let data = try await provider.encodedRequestForTesting(ModelRequest(
            messages: [
                .user("do both"),
                .assistant(text: "", toolCalls: [
                    ToolCall(id: "a", name: "one", arguments: "{}"),
                    ToolCall(id: "b", name: "two", arguments: "{}"),
                ]),
                .toolResult(ToolResult(callID: "a", content: "first")),
                .toolResult(ToolResult(callID: "b", content: "second")),
            ],
            tools: []
        ))
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.count == 3)
        let blocks = try #require(messages[2]["content"] as? [[String: Any]])
        #expect(blocks.count == 2, "both answers belong to one turn")
    }

    /// An error the vendor sends mid-stream is a provider error, not silence.
    @Test func avendorErrorMidStreamIsRaised() {
        var mapper = MessagesEventMapper()
        #expect(throws: ProviderError.vendor(type: "overloaded_error", message: "try later")) {
            try mapper.map(ServerSentEvent(
                type: "error",
                data: #"{"type":"error","error":{"type":"overloaded_error","message":"try later"}}"#
            ))
        }
    }
}

/// The conversion itself, run against the bytes a vendor really sent. The
/// recordings above prove a conversation replays; these prove the wire is read
/// the way the vendor writes it.
@Suite struct ReadingWhatTheVendorsReallySent {
    private func events(
        _ recording: String,
        through map: (ServerSentEvent) throws -> [StreamEvent],
        finishing done: () -> [StreamEvent] = { [] }
    ) throws -> [StreamEvent] {
        let url = try #require(Bundle.module.url(
            forResource: "Fixtures/\(recording)", withExtension: "sse"
        ))
        var parser = ServerSentEventParser()
        var events: [StreamEvent] = []
        let text = try String(contentsOf: url, encoding: .utf8)
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if let event = parser.consume(String(line)) { events += try map(event) }
        }
        if let last = parser.finish() { events += try map(last) }
        return events + done()
    }

    @Test func theOlderOpenAIShapeIsRead() throws {
        var mapper = ChatCompletionsEventMapper()
        let events = try events(
            "deepseek-v4-flash-tool-call",
            through: { try mapper.map($0) },
            finishing: { mapper.done() }
        )
        let calls = events.compactMap { if case .toolCall(let call) = $0 { call } else { nil } }
        #expect(calls.count == 1)
        #expect(calls[0].name == "weather")
        #expect(calls[0].arguments.contains("Paris"), "the fragments were put back together")
        #expect(calls[0].id.hasPrefix("call_"))
        // This vendor thinks out loud, and thinking is not the answer.
        #expect(events.contains { if case .reasoning = $0 { true } else { false } })
        #expect(events.contains { if case .usage(let usage) = $0 { usage.totalTokens > 0 } else { false } })
        // What every provider must end with, in the same order.
        #expect(events.last == .stop(.toolUse))
        let usageAt = events.lastIndex { if case .usage = $0 { true } else { false } }
        #expect(usageAt == events.count - 2, "what it cost is said before the stop, as everywhere else")
    }

    @Test func theMessagesShapeIsRead() throws {
        var mapper = MessagesEventMapper()
        let events = try events("minimax-m3-tool-call", through: { try mapper.map($0) })
        let calls = events.compactMap { if case .toolCall(let call) = $0 { call } else { nil } }
        #expect(calls.count == 1)
        #expect(calls[0].name == "weather")
        #expect(calls[0].arguments.contains("Paris"))
        // This recording went straight for the tool, which is allowed: what
        // matters is that the call and the count came through whole.
        #expect(events.contains { if case .usage(let usage) = $0 { usage.totalTokens > 0 } else { false } })
        #expect(events.last == .stop(.toolUse))
        let usageAt = events.lastIndex { if case .usage = $0 { true } else { false } }
        #expect(usageAt == events.count - 2)
    }

    /// The newer shape, for the same three claims, so a change to one is
    /// caught against all of them.
    @Test func theNewerOpenAIShapeIsRead() throws {
        var mapper = ResponsesEventMapper()
        let events = try events("muse-spark-1.3-tool-call", through: { try mapper.map($0) })
        let calls = events.compactMap { if case .toolCall(let call) = $0 { call } else { nil } }
        #expect(calls.count == 1)
        #expect(calls[0].arguments.contains("Paris"))
        #expect(events.last == .stop(.toolUse))
        let usageAt = events.lastIndex { if case .usage = $0 { true } else { false } }
        #expect(usageAt == events.count - 2)
    }
}
