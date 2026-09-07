import Foundation
import Swaco

/// A tool of an app's own, a toolset of them, and how they are handed over.
///
/// This is the shape to copy. It is a template, not a shipped capability:
/// swaco carries no tools, because what an agent is for is the app's to say.
///
/// Everything here uses the same public protocols a companion or a third party
/// has. If writing one of these ever needed a private path, the core would be
/// deficient and the core would be fixed.

// MARK: - One tool

/// A tool that answers at once. Most tools are this shape: arguments in, a
/// result out, nothing to wait for.
public struct NoteDown: Tool {
    public let name = "note_down"
    public let description = "Write a short note into the app's own list"
    /// Declared, never guessed. Extensions and the app read this; the loop
    /// acts on it in no way.
    public let access = ToolAccess.writing
    public let parameters = """
    {"type":"object","properties":{\
    "note":{"type":"string","description":"What to write down"}},\
    "required":["note"]}
    """

    /// Where the app keeps its notes. A tool reaches the app's own world
    /// through what the app hands it, never through swaco.
    private let notes: Notes

    public init(notes: Notes) {
        self.notes = notes
    }

    public func execute(
        _ call: ToolCall,
        delivering delivery: ResultDelivery
    ) async throws -> ToolOutcome {
        let asked = try JSONDecoder().decode(Arguments.self, from: Data(call.arguments.utf8))
        await notes.add(asked.note)
        return .result(ToolResult(callID: call.id, content: "written down"))
    }

    private struct Arguments: Decodable { let note: String }

    /// The app's own store, which swaco knows nothing about.
    public actor Notes {
        private(set) var written: [String] = []
        public init() {}
        public func add(_ note: String) { written.append(note) }
        public var all: [String] { written }
    }
}

/// A tool whose answer comes later, from outside the process that asked.
///
/// The two methods are the whole of it. `execute` registers what will deliver
/// the result and says `.deferred`; `resume` is handed the same call in a
/// fresh process and arms it again. That pair is what lets a wait outlive the
/// app that started it.
public struct WaitForTheDoor: Tool {
    public let name = "wait_for_the_door"
    public let description = "Wait until someone opens the door"
    public let access = ToolAccess.readOnly

    private let door: Door

    public init(door: Door) {
        self.door = door
    }

    public func execute(
        _ call: ToolCall,
        delivering delivery: ResultDelivery
    ) async throws -> ToolOutcome {
        await door.expect(call, delivering: delivery)
        return .deferred
    }

    public func resume(
        _ call: ToolCall,
        delivering delivery: ResultDelivery
    ) async throws {
        // A new process, a new door, the same call: arm it again.
        await door.expect(call, delivering: delivery)
    }

    /// Whatever the app has that will one day say the door opened: a
    /// notification, a sensor, a person.
    public actor Door {
        private var expected: [String: ResultDelivery] = [:]
        public init() {}

        func expect(_ call: ToolCall, delivering delivery: ResultDelivery) {
            expected[call.id] = delivery
        }

        /// The app calls this when the thing happens.
        public func opened(by who: String) async {
            let waiting = expected
            expected = [:]
            for (callID, delivery) in waiting {
                await delivery(ToolResult(callID: callID, content: "opened by \(who)"))
            }
        }
    }
}

// MARK: - A toolset of them

/// A named group, which is what an app hands to an agent.
///
/// Coarse on purpose: one set for one part of the app's world. An app that
/// wants part of it says so at the granularity of a tool, with `only` or
/// `except`, rather than being offered a dozen half-sets.
public struct HouseholdTools: ToolSet {
    public let name = "household"
    public let description = "Notes and the front door"
    public let tools: [any Tool]

    public init(notes: NoteDown.Notes, door: WaitForTheDoor.Door) {
        tools = [NoteDown(notes: notes), WaitForTheDoor(door: door)]
    }
}

// MARK: - An extension of the app's own

/// An extension that keeps the model from being told about the same tool
/// twice, as a small example of the shape.
///
/// The hooks are the moments of the loop. This one uses the request, passes
/// everything it does not care about, and says who it is so the log can name
/// it.
public struct DropDuplicateTools: Extension {
    public let name = "drop-duplicate-tools"

    public init() {}

    public func beforeRequest(
        _ request: ModelRequest,
        in context: ExtensionContext
    ) async -> Decision<ModelRequest> {
        var seen: Set<String> = []
        let once = request.tools.filter { seen.insert($0.name).inserted }
        guard once.count != request.tools.count else { return .pass }
        return .rewrite(ModelRequest(messages: request.messages, tools: once, content: request.content))
    }
}
