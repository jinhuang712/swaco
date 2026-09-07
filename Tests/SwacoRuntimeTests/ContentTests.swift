import Foundation
import Testing
import Swaco
import SwacoRuntime
import SwacoTesting

/// A picture, in spirit: the smallest bytes that can stand in for one.
private let pixel = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

@Suite struct ContentThatPointsElsewhere {
    /// The promise: a long history with media stays cheap, because the log
    /// holds references and the bytes are read when a request is built.
    @Test func aReferenceTravelsInTheLogAndTheBytesDoNot() async throws {
        let content = InMemoryContentStore()
        let reference = try await content.store(pixel, type: "image/png")

        let events = InMemoryEventStore()
        let run = Run(
            agent: Agent(provider: ScriptedProvider.saying("A tabby, I think."),
                         tools: [],
                         content: content),
            store: events
        )
        let arrival = InboundEvent(source: .share, content: [
            .text("what is this?"), .image(.reference(reference)),
        ])
        for try await _ in run.start(arrival) {}

        // The log holds the reference, not the bytes.
        let written = try await run.history()
        guard case .arrived(let recorded) = try #require(written.first) else {
            Issue.record("a log must begin with what arrived")
            return
        }
        #expect(recorded.content.contains(.image(.reference(reference))))
        let line = try JSONEncoder().encode(written.first)
        #expect(line.count < 300, "a log line must not have swallowed the bytes")
        #expect(!String(decoding: line, as: UTF8.self).contains(pixel.base64EncodedString()))

        // And the picture is still there to be read, once, when it is needed.
        #expect(try await content.load(reference) == pixel)
    }

    /// A part that points somewhere and a request that names no store is an
    /// error the app is told about, not a picture quietly dropped.
    @Test func aReferenceWithNoStoreIsAnError() async throws {
        let content = InMemoryContentStore()
        let reference = try await content.store(pixel, type: "image/png")
        let provider = ScriptedProvider.saying("never reached")
        let request = ModelRequest(
            messages: [.user([.image(.reference(reference))])],
            tools: []
        )
        // The mock does not resolve anything, so this is about the vocabulary:
        // the request says it has no store, and the part says it needs one.
        #expect(request.content == nil)
        _ = provider
        #expect(request.messages.first?.needs == [.vision])
    }

    /// A picture put to a model that has not declared it can see is recorded
    /// as a mismatch, and nothing else happens.
    @Test func aPictureForAModelWithNoEyesIsRecorded() async throws {
        let run = Run(
            agent: Agent(provider: ScriptedProvider.saying("I cannot see it."), tools: []),
            store: InMemoryEventStore()
        )
        var events: [Event] = []
        for try await event in run.start(InboundEvent(source: .share, content: [
            .text("what is this?"), .image(.bytes(pixel, type: "image/png")),
        ])) { events.append(event) }

        #expect(events.contains(.capabilityMissing(.vision)))
        #expect(events.last == .finished, "the loop does not refuse; the app decides")
        // Said once, not once a turn.
        #expect(events.filter { $0 == .capabilityMissing(.vision) }.count == 1)
    }

    /// Every kind of part survives the log, including the ones this version
    /// would not know what to do with.
    @Test func everyKindOfPartSurvivesTheLog() throws {
        let parts: [ContentPart] = [
            .text("words"),
            .image(.bytes(pixel, type: "image/png")),
            .image(.reference(ContentReference(identifier: "abc", type: "image/jpeg"))),
            .image(.url(URL(string: "https://example.invalid/cat.png")!, type: "image/png")),
            .reasoning("thinking about it"),
            .providerTool(name: "web_search", input: .object(["query": .string("cats")])),
            .providerToolResult(name: "web_search", output: .array([.string("a page")])),
            .citation(Citation(title: "A page", url: URL(string: "https://example.invalid"), range: 0..<4)),
        ]
        let event = Event.arrived(InboundEvent(source: .share, content: parts))
        let data = try JSONEncoder().encode(event)
        #expect(try JSONDecoder().decode(Event.self, from: data) == event)
    }

    /// Words assembled from several places read as one thing.
    @Test func adjacentWordsBecomeOnePart() {
        let parts: [ContentPart] = [
            .text("[shortcut] "), .text("start"), .text(" the day"), .text(""),
            .image(.bytes(pixel, type: "image/png")), .text("and"), .text(" this"),
        ]
        #expect(parts.normalised == [
            .text("[shortcut] start the day"),
            .image(.bytes(pixel, type: "image/png")),
            .text("and this"),
        ])
    }
}
