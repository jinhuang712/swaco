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
public struct ToolResult: Sendable, Codable, Hashable {
    public let callID: String
    public let content: String
    public let isError: Bool

    public init(callID: String, content: String, isError: Bool = false) {
        self.callID = callID
        self.content = content
        self.isError = isError
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
public protocol Tool: Sendable {
    var name: String { get }
    var description: String { get }
    var access: ToolAccess { get }

    func execute(_ call: ToolCall, delivering delivery: ResultDelivery) async throws -> ToolOutcome
    func resume(_ call: ToolCall, delivering delivery: ResultDelivery) async throws
}

public extension Tool {
    /// Tools that always answer at once have nothing to resume.
    func resume(_ call: ToolCall, delivering delivery: ResultDelivery) async throws {}
}
