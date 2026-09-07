import Foundation
import Swaco

/// The request body of the chat-completions protocol, the older of the two
/// OpenAI shapes and the one most other vendors copied.
struct ChatCompletionsRequest: Encodable {
    let model: String
    let messages: [Wire]
    let tools: [ToolSpec]?
    let stream = true
    let streamOptions = StreamOptions()
    let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model, messages, tools, stream
        case streamOptions = "stream_options"
        case maxTokens = "max_tokens"
    }

    /// Usage arrives only if it is asked for.
    struct StreamOptions: Encodable {
        let includeUsage = true
        enum CodingKeys: String, CodingKey { case includeUsage = "include_usage" }
    }

    init(model: String, request: ModelRequest, maxTokens: Int) async throws {
        self.model = model
        self.maxTokens = maxTokens
        self.tools = request.tools.isEmpty ? nil : request.tools.map(ToolSpec.init)
        var wire: [Wire] = []
        for message in request.messages {
            wire += try await Wire.messages(for: message, resolving: request.content)
        }
        self.messages = wire
    }

    func encoded() throws -> Data { try JSONEncoder().encode(self) }

    /// A tool, wrapped the way this protocol wraps them.
    struct ToolSpec: Encodable {
        let type = "function"
        let function: Function

        init(_ definition: ToolDefinition) {
            function = Function(
                name: definition.name,
                description: definition.description,
                parameters: JSONText(definition.parameters)
            )
        }

        struct Function: Encodable {
            let name: String
            let description: String
            let parameters: JSONText
        }
    }

    /// One message on the wire. Roles and a tool's answer, which this protocol
    /// carries as a message of its own rather than as an item.
    enum Wire: Encodable {
        case text(role: String, String)
        /// Words and pictures together, which this protocol allows only from
        /// a person.
        case parts(role: String, [Part])
        case assistant(text: String, calls: [ToolCall])
        case toolResult(callID: String, output: String)

        static func messages(
            for message: Message,
            resolving content: (any ContentStore)?
        ) async throws -> [Wire] {
            switch message {
            case .system(let text):
                return [.text(role: "system", text)]
            case .user(let parts):
                let wired = try await Part.wire(parts, resolving: content)
                if wired.count == 1, case .text(let only) = wired[0] {
                    return [.text(role: "user", only)]
                }
                return [.parts(role: "user", wired)]
            case .assistant(let parts, let calls):
                guard !parts.text.isEmpty || !calls.isEmpty else { return [] }
                return [.assistant(text: parts.text, calls: calls)]
            case .toolResult(let result):
                return [.toolResult(callID: result.callID, output: result.content)]
            }
        }

        private enum Key: String, CodingKey {
            case role, content, name, arguments, id, type, function
            case toolCalls = "tool_calls"
            case toolCallID = "tool_call_id"
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: Key.self)
            switch self {
            case .text(let role, let text):
                try container.encode(role, forKey: .role)
                try container.encode(text, forKey: .content)
            case .parts(let role, let parts):
                try container.encode(role, forKey: .role)
                try container.encode(parts, forKey: .content)
            case .assistant(let text, let calls):
                try container.encode("assistant", forKey: .role)
                try container.encode(text, forKey: .content)
                if !calls.isEmpty {
                    var wire = container.nestedUnkeyedContainer(forKey: .toolCalls)
                    for call in calls {
                        var entry = wire.nestedContainer(keyedBy: Key.self)
                        try entry.encode(call.id, forKey: .id)
                        try entry.encode("function", forKey: .type)
                        var function = entry.nestedContainer(keyedBy: Key.self, forKey: .function)
                        try function.encode(call.name, forKey: .name)
                        try function.encode(call.arguments, forKey: .arguments)
                    }
                }
            case .toolResult(let callID, let output):
                try container.encode("tool", forKey: .role)
                try container.encode(callID, forKey: .toolCallID)
                try container.encode(output, forKey: .content)
            }
        }

        /// One part of a message that carries more than words.
        enum Part: Encodable {
            case text(String)
            case image(url: String)

            static func wire(
                _ parts: [ContentPart],
                resolving content: (any ContentStore)?
            ) async throws -> [Part] {
                var wired: [Part] = []
                for part in parts {
                    switch part {
                    case .text(let text) where !text.isEmpty:
                        wired.append(.text(text))
                    case .image(let source):
                        wired.append(.image(url: try await Self.url(of: source, resolving: content)))
                    case .text, .reasoning, .citation, .providerTool, .providerToolResult:
                        continue
                    }
                }
                return wired
            }

            private static func url(
                of source: ContentSource,
                resolving content: (any ContentStore)?
            ) async throws -> String {
                switch source {
                case .bytes(let data, let type):
                    return "data:\(type);base64,\(data.base64EncodedString())"
                case .url(let url, _):
                    return url.absoluteString
                case .reference(let reference):
                    guard let content else { throw ProviderError.noContentStore(reference) }
                    let data = try await content.load(reference)
                    return "data:\(reference.type);base64,\(data.base64EncodedString())"
                }
            }

            private enum Key: String, CodingKey {
                case type, text
                case imageURL = "image_url"
                case url
            }

            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: Key.self)
                switch self {
                case .text(let text):
                    try container.encode("text", forKey: .type)
                    try container.encode(text, forKey: .text)
                case .image(let url):
                    try container.encode("image_url", forKey: .type)
                    var nested = container.nestedContainer(keyedBy: Key.self, forKey: .imageURL)
                    try nested.encode(url, forKey: .url)
                }
            }
        }
    }
}
