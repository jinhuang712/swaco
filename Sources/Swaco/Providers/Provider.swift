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

/// What a model has declared it can take. Facts, not policy: swaco makes sure
/// they are visible, and the app decides what to do when they do not line up.
public struct ModelCapabilities: Sendable, Hashable, Codable {
    public var tools: Bool
    public var vision: Bool
    public var reasoning: Bool
    /// Tools the vendor runs itself, such as its own web search.
    public var providerExecutedTools: Bool
    /// How much the model can be given, in tokens, where the vendor says.
    public var contextSize: Int?

    public init(
        tools: Bool = true,
        vision: Bool = false,
        reasoning: Bool = false,
        providerExecutedTools: Bool = false,
        contextSize: Int? = nil
    ) {
        self.tools = tools
        self.vision = vision
        self.reasoning = reasoning
        self.providerExecutedTools = providerExecutedTools
        self.contextSize = contextSize
    }

    /// A model that takes text and can be given tools.
    public static let text = ModelCapabilities()
}

/// Whether a model can be used at all, asked before the first request rather
/// than discovered after the first failure.
public enum ModelAvailability: Sendable, Hashable {
    case ready
    /// Not on this device, or not turned on, or still arriving. The string
    /// says which, in the vendor's terms.
    case unavailable(String)
    case downloading
}

/// The translation between swaco's vocabulary and one model API: one
/// streaming call.
public protocol Provider: Sendable {
    /// What this model has declared. New capabilities arrive with defaults, so
    /// a provider written against an older swaco keeps compiling.
    var capabilities: ModelCapabilities { get }
    /// Whether it can be used now.
    var availability: ModelAvailability { get }
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<StreamEvent, any Error>
}

public extension Provider {
    var capabilities: ModelCapabilities { .text }
    var availability: ModelAvailability { .ready }
}
