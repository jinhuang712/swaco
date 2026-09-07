import Foundation

/// Whether a tool only reads or may write. A fact for extensions and the app;
/// the loop acts on it in no way.
public enum ToolAccess: Sendable, Codable, Hashable {
    case readOnly
    case writing
}

/// A request from the model to have a tool run.
public struct ToolCall: Sendable, Codable, Hashable {
    public let id: String
    public let name: String
    /// JSON text of the arguments, exactly as the model produced it.
    public let arguments: String

    public init(id: String, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

/// What a tool produced for one call.
///
/// Two readers, and they want different things. A model reads `content`,
/// because every vendor's protocol carries a tool's answer as text. An app
/// reads `data` when the tool gave one, because a list of events is more
/// useful to a screen as a list than as a paragraph.
///
/// Swaco does not choose between them and does not translate one into the
/// other beyond writing the structure down as JSON. What a model should be
/// told is the tool's business; what a screen should show is the app's.
public struct ToolResult: Sendable, Codable, Hashable {
    public let callID: String
    /// What the model is told.
    public let content: String
    public let isError: Bool
    /// What the tool actually produced, where it produced something with a
    /// shape. Recorded in the log beside the words, so an app reading the
    /// history later has it too.
    public let data: JSONValue?

    public init(callID: String, content: String, isError: Bool = false, data: JSONValue? = nil) {
        self.callID = callID
        self.content = content
        self.isError = isError
        self.data = data
    }

    /// A result with a shape: the value is written down for the app, and the
    /// same JSON is what the model is told, unless the tool says otherwise.
    ///
    /// - Parameter saying: what to tell the model, when the JSON is not the
    ///   best thing to say to it. A model reading "3 events" understands
    ///   faster than one reading an array, and the app still gets the array.
    public init(
        callID: String,
        _ value: some Encodable & Sendable,
        saying content: String? = nil,
        isError: Bool = false
    ) throws {
        let data = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
        let words = try content ?? data.jsonText
        self.init(callID: callID, content: words, isError: isError, data: data)
    }

    /// The structure the tool produced, read back as the type it was.
    public func data<Value: Decodable>(as type: Value.Type = Value.self) throws -> Value? {
        guard let data else { return nil }
        return try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(data))
    }
}

/// What `execute` returns: the result now, or a promise that it arrives later
/// through the delivery the tool was handed.
public enum ToolOutcome: Sendable {
    case result(ToolResult)
    case deferred
}

/// The one way a result reaches the loop after `execute` has returned.
/// Sendable and value-typed so a tool can hold it across a process boundary
/// only in spirit: in a fresh process the loop hands a new one to `resume`.
public struct ResultDelivery: Sendable {
    let deliver: @Sendable (ToolResult) async -> Void

    /// Delivers the result. Called like a function, because a tool that
    /// says `await delivery(result)` reads as what it is.
    public func callAsFunction(_ result: ToolResult) async {
        await deliver(result)
    }
}

/// Something the model can ask to have done.
///
/// Execution is a pair of events, never an awaited function: the loop records
/// the call, asks the tool to execute, and advances only when a result event
/// exists. A tool that cannot answer at once returns `.deferred` and later
/// calls the delivery. `resume` is how a deferred call is re-armed in a fresh
/// process: given the call it once registered, arrange for the result to be
/// delivered again.
public protocol Tool: ToolSet {
    var name: String { get }
    var description: String { get }
    var access: ToolAccess { get }
    /// JSON Schema for the arguments, as JSON text. The core does not model
    /// schemas; it carries what the app wrote to whatever provider is in use.
    var parameters: String { get }

    func execute(_ call: ToolCall, delivering delivery: ResultDelivery) async throws -> ToolOutcome
    func resume(_ call: ToolCall, delivering delivery: ResultDelivery) async throws
}

public extension Tool {
    /// Tools that always answer at once have nothing to resume.
    func resume(_ call: ToolCall, delivering delivery: ResultDelivery) async throws {}

    /// A tool that takes no arguments.
    var parameters: String { #"{"type":"object","properties":{}}"# }

    /// A single tool is a toolset of one.
    var tools: [any Tool] { [self] }
}
