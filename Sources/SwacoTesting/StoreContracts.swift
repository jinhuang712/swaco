import Foundation
import Testing
import Swaco

/// The contract every `EventStore` must meet, whoever wrote it. A companion or
/// a third party runs this against its own store; so do our reference
/// implementations, so the contract is never only words.
///
/// `make` is called for each check and must return an empty store. `reopen`
/// returns a store over the same medium, so durability is checked the only way
/// that means anything: by looking again through something else.
public struct EventStoreContract<Store: EventStore>: Sendable {
    let make: @Sendable () async throws -> Store
    let reopen: @Sendable (Store) async throws -> Store

    public init(
        make: @Sendable @escaping () async throws -> Store,
        reopen: @Sendable @escaping (Store) async throws -> Store = { $0 }
    ) {
        self.make = make
        self.reopen = reopen
    }

    /// Runs every check. A failure is reported against the caller's test.
    public func verify(sourceLocation: SourceLocation = #_sourceLocation) async throws {
        try await appendsKeepTheirOrder(sourceLocation)
        try await readingFromAPositionSkipsWhatWasRead(sourceLocation)
        try await groupsDoNotSeeEachOther(sourceLocation)
        try await whatIsAppendedIsDurable(sourceLocation)
        try await anUnknownEventTypeSurvives(sourceLocation)
    }

    private func appendsKeepTheirOrder(_ location: SourceLocation) async throws {
        let store = try await make()
        let events: [Event] = [.turnStarted(1), .text("a"), .text("b"), .finished]
        for event in events { try await store.append(event, to: "g") }
        let stored = try await store.read("g")
        #expect(stored.map(\.event) == events, "appends must keep their order", sourceLocation: location)
        #expect(stored.map(\.position) == [0, 1, 2, 3], "positions must increase", sourceLocation: location)
    }

    private func readingFromAPositionSkipsWhatWasRead(_ location: SourceLocation) async throws {
        let store = try await make()
        try await store.append([.turnStarted(1), .text("a")], to: "g")
        let first = try await store.read("g")
        try await store.append([.text("b"), .finished], to: "g")
        let rest = try await store.read("g", after: first.last?.position)
        #expect(rest.map(\.event) == [.text("b"), .finished],
                "reading from a position must return only what came after it", sourceLocation: location)
    }

    private func groupsDoNotSeeEachOther(_ location: SourceLocation) async throws {
        let store = try await make()
        try await store.append(.text("one"), to: "a")
        try await store.append(.text("two"), to: "b")
        let a = try await store.read("a")
        #expect(a.map(\.event) == [.text("one")], "a group must hold only its own events", sourceLocation: location)
        let groups = Set(try await store.groups().map(\.rawValue))
        #expect(groups == ["a", "b"], "every group written must be listed", sourceLocation: location)
    }

    private func whatIsAppendedIsDurable(_ location: SourceLocation) async throws {
        let store = try await make()
        try await store.append([.turnStarted(1), .text("kept")], to: "g")
        let reopened = try await reopen(store)
        let stored = try await reopened.read("g")
        #expect(stored.map(\.event) == [.turnStarted(1), .text("kept")],
                "what append returned from must still be there", sourceLocation: location)
    }

    private func anUnknownEventTypeSurvives(_ location: SourceLocation) async throws {
        let store = try await make()
        let fromTheFuture = Event.unrecognised(
            type: "not_yet_invented",
            fields: ["detail": .string("kept"), "count": .number(2)]
        )
        try await store.append([.turnStarted(1), fromTheFuture, .finished], to: "g")
        let stored = try await reopen(store).read("g")
        #expect(stored.map(\.event) == [.turnStarted(1), fromTheFuture, .finished],
                "an event type this swaco does not know must survive unchanged", sourceLocation: location)
    }
}

/// The contract every `ContentStore` must meet.
public struct ContentStoreContract<Store: ContentStore>: Sendable {
    let make: @Sendable () async throws -> Store
    let reopen: @Sendable (Store) async throws -> Store

    public init(
        make: @Sendable @escaping () async throws -> Store,
        reopen: @Sendable @escaping (Store) async throws -> Store = { $0 }
    ) {
        self.make = make
        self.reopen = reopen
    }

    public func verify(sourceLocation: SourceLocation = #_sourceLocation) async throws {
        let store = try await make()
        let bytes = Data("a picture, in spirit".utf8)
        let reference = try await store.store(bytes, type: "image/png")
        #expect(try await store.load(reference) == bytes,
                "loading a reference must return the bytes stored", sourceLocation: sourceLocation)
        #expect(reference.type == "image/png",
                "a reference must carry the kind of bytes it points at", sourceLocation: sourceLocation)

        let reopened = try await reopen(store)
        #expect(try await reopened.load(reference) == bytes,
                "a reference must stay valid", sourceLocation: sourceLocation)

        try await reopened.remove(reference)
        await #expect(throws: StoreError.noSuchContent(reference),
                      "a removed reference must fail, not return nothing", sourceLocation: sourceLocation) {
            try await reopened.load(reference)
        }
    }
}
