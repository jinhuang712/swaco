/// Why a loop stopped before the model did.
public enum CancellationOrigin: Sendable, Hashable {
    case person
    case system
}

/// Everything that leaves the agent, in the order it happened.
public enum Event: Sendable, Hashable {
    case turnStarted(Int)
    case text(String)
    case toolCallIssued(ToolCall)
    case toolCallDeferred(ToolCall)
    case toolResultArrived(ToolResult)
    case turnEnded(StopReason)
    case cancelled(CancellationOrigin, partial: String)
    case failed(String)
    case finished
    /// An event written by a swaco that knew a type this one does not. Kept
    /// exactly as it was written, and written back unchanged.
    case unrecognised(type: String, fields: [String: JSONValue])
}
