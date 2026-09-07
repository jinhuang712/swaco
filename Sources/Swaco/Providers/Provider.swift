/// Why the model stopped producing.
public enum StopReason: Sendable, Hashable {
    case endTurn
    case toolUse
    case maxTokens
}

/// What a turn cost, as the vendor counted it.
///
/// Swaco carries these and does nothing with them: it does not price them, add
/// them up across runs, or decide when there have been too many. Accounting
/// and quality are not ours; the numbers are facts, and an app or an extension
/// does what its product requires with them.
public struct Usage: Sendable, Hashable, Codable {
    public var inputTokens: Int
    public var outputTokens: Int
    /// The part of the input the vendor says it had already cached.
    public var cachedInputTokens: Int
    /// The part of the output that was thinking rather than answering.
    public var reasoningTokens: Int

    public init(
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cachedInputTokens: Int = 0,
        reasoningTokens: Int = 0
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedInputTokens = cachedInputTokens
        self.reasoningTokens = reasoningTokens
    }

    public var totalTokens: Int { inputTokens + outputTokens }

    public static func + (left: Usage, right: Usage) -> Usage {
        Usage(
            inputTokens: left.inputTokens + right.inputTokens,
            outputTokens: left.outputTokens + right.outputTokens,
            cachedInputTokens: left.cachedInputTokens + right.cachedInputTokens,
            reasoningTokens: left.reasoningTokens + right.reasoningTokens
        )
    }
}

/// The canonical streaming event set every provider produces.
///
/// Written down as well as passed around: a recorded exchange is how
/// development, previews and tests do without a key and a network, so its
/// names are stable on the same terms as the event log's.
public enum StreamEvent: Sendable, Hashable {
    case text(String)
    case toolCall(ToolCall)
    /// What the vendor thought on the way, where it gives it to us.
    case reasoning(String)
    case usage(Usage)
    case stop(StopReason)
}

/// One message in the context sent to a model, projected from the events that
/// happened rather than stored beside them.
public enum Message: Sendable, Codable, Hashable {
    /// Standing instructions, ahead of the conversation.
    case system(String)
    case user([ContentPart])
    case assistant(content: [ContentPart], toolCalls: [ToolCall])
    case toolResult(ToolResult)

    /// What a person said, in words.
    public static func user(_ text: String) -> Message {
        .user([.text(text)].normalised)
    }

    /// What the model said, in words.
    public static func assistant(text: String, toolCalls: [ToolCall]) -> Message {
        .assistant(content: text.isEmpty ? [] : [.text(text)], toolCalls: toolCalls)
    }

    /// The words in this message. Reading a conversation should not mean
    /// taking it apart.
    public var text: String {
        switch self {
        case .system(let text): text
        case .user(let content): content.text
        case .assistant(let content, _): content.text
        case .toolResult(let result): result.content
        }
    }

    /// What this message needs the model to be able to take.
    public var needs: Set<Capability> {
        switch self {
        case .user(let content), .assistant(let content, _):
            Set(content.compactMap(\.needs))
        case .system, .toolResult:
            []
        }
    }
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
    /// Where a part that points at bytes is resolved. A provider fetches
    /// through this and holds no store of its own; nil means nothing in this
    /// request points anywhere.
    public let content: (any ContentStore)?

    public init(
        messages: [Message],
        tools: [ToolDefinition],
        content: (any ContentStore)? = nil
    ) {
        self.messages = messages
        self.tools = tools
        self.content = content
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

/// A model as data: who serves it, what it is called there, and what it has
/// declared. Enough to choose one, pass one around, or write one down; not a
/// provider, and not a connection.
public struct Model: Sendable, Hashable, Codable {
    /// Who serves it, in swaco's terms rather than a vendor's branding:
    /// "openai", "anthropic", "apple", or an app's own name for its backend.
    public let provider: String
    /// What the provider calls it.
    public let identifier: String
    public let capabilities: ModelCapabilities

    public init(provider: String, identifier: String, capabilities: ModelCapabilities) {
        self.provider = provider
        self.identifier = identifier
        self.capabilities = capabilities
    }
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
