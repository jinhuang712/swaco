/// Why the model stopped producing.
public enum StopReason: Sendable, Hashable {
    case endTurn
    case toolUse
    case maxTokens
}

/// The canonical streaming event set every provider produces.
public enum StreamEvent: Sendable, Hashable {
    case text(String)
    case toolCall(ToolCall)
    case stop(StopReason)
}

/// One message in the context sent to a model. A projection of events, kept
/// minimal for the spike.
public enum Message: Sendable, Codable, Hashable {
    case user(String)
    case assistant(text: String, toolCalls: [ToolCall])
    case toolResult(ToolResult)
}

public struct ToolDefinition: Sendable, Codable, Hashable {
    public let name: String
    public let description: String
    /// JSON Schema for the arguments, as JSON text.
    public let parameters: String

    public init(name: String, description: String, parameters: String) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

public struct ModelRequest: Sendable {
    public let messages: [Message]
    public let tools: [ToolDefinition]

    public init(messages: [Message], tools: [ToolDefinition]) {
        self.messages = messages
        self.tools = tools
    }
}

/// The translation between swaco's vocabulary and one model API: one
/// streaming call.
public protocol Provider: Sendable {
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<StreamEvent, any Error>
}
