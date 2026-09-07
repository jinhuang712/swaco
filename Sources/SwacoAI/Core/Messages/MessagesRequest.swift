import Foundation
import Swaco

/// The request body of the Messages protocol, Anthropic's shape and the one
/// several other vendors now speak.
struct MessagesRequest: Encodable {
    let model: String
    let system: String?
    let messages: [Wire]
    let tools: [ToolSpec]?
    let maxTokens: Int
    let stream = true

    enum CodingKeys: String, CodingKey {
        case model, system, messages, tools, stream
        case maxTokens = "max_tokens"
    }

    init(model: String, request: ModelRequest, maxTokens: Int) async throws {
        self.model = model
        self.maxTokens = maxTokens
        self.tools = request.tools.isEmpty ? nil : request.tools.map(ToolSpec.init)

        // Instructions are their own field here, not a message.
        var instructions: [String] = []
        var wire: [Wire] = []
        for message in request.messages {
            if case .system(let text) = message {
                instructions.append(text)
                continue
            }
            wire += try await Wire.messages(for: message, resolving: request.content)
        }
        self.system = instructions.isEmpty ? nil : instructions.joined(separator: "\n\n")
        self.messages = Wire.merged(wire)
    }

    func encoded() throws -> Data { try JSONEncoder().encode(self) }

    struct ToolSpec: Encodable {
        let name: String
        let description: String
        let inputSchema: JSONText

        enum CodingKeys: String, CodingKey {
            case name, description
            case inputSchema = "input_schema"
        }

        init(_ definition: ToolDefinition) {
            name = definition.name
            description = definition.description
            inputSchema = JSONText(definition.parameters)
        }
    }

    /// One message: a role, and the blocks it is made of.
    struct Wire: Encodable {
        let role: String
        let content: [Block]

        static func messages(
            for message: Message,
            resolving content: (any ContentStore)?
        ) async throws -> [Wire] {
            switch message {
            case .system:
                return []
            case .user(let parts):
                let blocks = try await Block.blocks(of: parts, resolving: content)
                return blocks.isEmpty ? [] : [Wire(role: "user", content: blocks)]
            case .assistant(let parts, let calls):
                var blocks = try await Block.blocks(of: parts, resolving: content)
                blocks += calls.map { .toolUse(id: $0.id, name: $0.name, input: $0.arguments) }
                return blocks.isEmpty ? [] : [Wire(role: "assistant", content: blocks)]
            case .toolResult(let result):
                // A tool's answer comes back as a block of a person's message,
                // which is this protocol's way rather than a role of its own.
                return [Wire(role: "user", content: [
                    .toolResult(id: result.callID, content: result.content, isError: result.isError),
                ])]
            }
        }

        /// Consecutive messages of one role become one, because this protocol
        /// will not take two in a row.
        static func merged(_ wire: [Wire]) -> [Wire] {
            wire.reduce(into: []) { merged, next in
                if let last = merged.last, last.role == next.role {
                    merged[merged.count - 1] = Wire(role: last.role, content: last.content + next.content)
                } else {
                    merged.append(next)
                }
            }
        }

        enum Block: Encodable {
            case text(String)
            case image(media: String, base64: String)
            case toolUse(id: String, name: String, input: String)
            case toolResult(id: String, content: String, isError: Bool)

            static func blocks(
                of parts: [ContentPart],
                resolving content: (any ContentStore)?
            ) async throws -> [Block] {
                var blocks: [Block] = []
                for part in parts {
                    switch part {
                    case .text(let text) where !text.isEmpty:
                        blocks.append(.text(text))
                    case .image(let source):
                        blocks.append(try await image(source, resolving: content))
                    case .text, .reasoning, .citation, .providerTool, .providerToolResult:
                        continue
                    }
                }
                return blocks
            }

            private static func image(
                _ source: ContentSource,
                resolving content: (any ContentStore)?
            ) async throws -> Block {
                switch source {
                case .bytes(let data, let type):
                    return .image(media: type, base64: data.base64EncodedString())
                case .url(let url, let type):
                    // This protocol takes bytes, so a URL is fetched rather
                    // than passed on.
                    let (data, _) = try await URLSession.shared.data(from: url)
                    return .image(media: type, base64: data.base64EncodedString())
                case .reference(let reference):
                    guard let content else { throw ProviderError.noContentStore(reference) }
                    let data = try await content.load(reference)
                    return .image(media: reference.type, base64: data.base64EncodedString())
                }
            }

            private enum Key: String, CodingKey {
                case type, text, source, id, name, input, content
                case toolUseID = "tool_use_id"
                case isError = "is_error"
                case mediaType = "media_type"
                case data
            }

            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: Key.self)
                switch self {
                case .text(let text):
                    try container.encode("text", forKey: .type)
                    try container.encode(text, forKey: .text)
                case .image(let media, let base64):
                    try container.encode("image", forKey: .type)
                    var source = container.nestedContainer(keyedBy: Key.self, forKey: .source)
                    try source.encode("base64", forKey: .type)
                    try source.encode(media, forKey: .mediaType)
                    try source.encode(base64, forKey: .data)
                case .toolUse(let id, let name, let input):
                    try container.encode("tool_use", forKey: .type)
                    try container.encode(id, forKey: .id)
                    try container.encode(name, forKey: .name)
                    try container.encode(JSONText(input), forKey: .input)
                case .toolResult(let id, let content, let isError):
                    try container.encode("tool_result", forKey: .type)
                    try container.encode(id, forKey: .toolUseID)
                    try container.encode(content, forKey: .content)
                    if isError { try container.encode(true, forKey: .isError) }
                }
            }
        }
    }
}
