import Foundation
import Testing
import Swaco
import SwacoRuntime
import SwacoConformance

/// Our own stores run the contract every third-party store runs. If the
/// contract is wrong, it is wrong for everyone at once.
@Suite struct ReferenceStores {
    @Test func inMemoryEventStoreMeetsTheContract() async throws {
        try await EventStoreContract(make: { InMemoryEventStore() }).verify()
    }

    @Test func fileEventStoreMeetsTheContract() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try await EventStoreContract(
            make: { try FileEventStore(directory: root.appending(path: UUID().uuidString)) },
            // A second store over the same directory: durability checked by
            // looking again through something that shares no memory.
            reopen: { try FileEventStore(directory: await $0.directory) }
        ).verify()
    }

    @Test func inMemoryContentStoreMeetsTheContract() async throws {
        try await ContentStoreContract(make: { InMemoryContentStore() }).verify()
    }

    @Test func fileContentStoreMeetsTheContract() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try await ContentStoreContract(
            make: { try FileContentStore(directory: root.appending(path: UUID().uuidString)) },
            reopen: { try FileContentStore(directory: await $0.directory) }
        ).verify()
    }

    private func temporaryDirectory() -> URL {
        URL.temporaryDirectory.appending(path: "swaco-tests-\(UUID().uuidString)")
    }
}

@Suite struct TheEventLogFormat {
    /// The format is public API: these are the names a log actually carries.
    @Test func namesOnTheWireAreWhatWePromise() throws {
        let written = try line(for: .turnEnded(.toolUse))
        #expect(written == #"{"stop":"tool_use","type":"turn_ended"}"#)
        #expect(try line(for: .text("hi")) == #"{"text":"hi","type":"text"}"#)
        #expect(try line(for: .finished) == #"{"type":"finished"}"#)
        #expect(try line(for: .cancelled(.person, partial: "half")) ==
                #"{"origin":"person","partial":"half","type":"cancelled"}"#)
    }

    @Test func everyEventRoundTrips() throws {
        let events: [Event] = [
            .turnStarted(3),
            .text("a reply"),
            .toolCallIssued(ToolCall(id: "c1", name: "weather", arguments: #"{"city":"Paris"}"#)),
            .toolCallDeferred(ToolCall(id: "c2", name: "ask", arguments: "{}")),
            .toolResultArrived(ToolResult(callID: "c1", content: "18C", isError: false)),
            .turnEnded(.maxTokens),
            .cancelled(.system, partial: "half a "),
            .failed("network"),
            .finished,
        ]
        for event in events {
            let data = try JSONEncoder().encode(event)
            #expect(try JSONDecoder().decode(Event.self, from: data) == event)
        }
    }

    /// A log written by a newer swaco is read by this one without loss.
    @Test func anEventFromTheFutureIsKeptAndWrittenBack() throws {
        let fromTheFuture = #"{"type":"budget_exhausted","turns":12,"detail":{"limit":10}}"#
        let event = try JSONDecoder().decode(Event.self, from: Data(fromTheFuture.utf8))
        guard case .unrecognised(let type, let fields) = event else {
            Issue.record("an unknown type must not be dropped or guessed at")
            return
        }
        #expect(type == "budget_exhausted")
        #expect(fields["turns"] == .number(12))
        #expect(fields["detail"] == .object(["limit": .number(10)]))

        let rewritten = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(event))
        let original = try JSONSerialization.jsonObject(with: Data(fromTheFuture.utf8))
        #expect((rewritten as? NSDictionary) == (original as? NSDictionary))
    }

    /// A line that is not an event at all is a store error naming where it is,
    /// not a crash and not a silent skip.
    @Test func aCorruptLineIsReportedWithItsPlace() async throws {
        let directory = URL.temporaryDirectory.appending(path: "swaco-corrupt-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try FileEventStore(directory: directory)
        try await store.append([.turnStarted(1)], to: "g")
        let file = directory.appending(path: "g.log")
        try (String(contentsOf: file, encoding: .utf8) + "not json\n").write(to: file, atomically: true, encoding: .utf8)

        await #expect(throws: StoreError.unreadable("g line 2")) {
            try await store.read("g")
        }
    }

    private func line(for event: Event) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return String(decoding: try encoder.encode(event), as: UTF8.self)
    }
}
