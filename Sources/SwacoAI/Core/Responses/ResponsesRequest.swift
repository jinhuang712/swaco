import Foundation
import Swaco

/// The request body of the OpenAI Responses protocol, built from swaco's
/// vocabulary. Conversion is lossless: ids are preserved so tool results
/// return to the call that asked for them.
struct ResponsesRequest: Encodable {
    let model: String
    let input: [InputItem]
    let tools: [ToolSpec]
    let stream: Bool
    let maxOutputTokens: Int

    enum CodingKeys: String, CodingKey {
        case model, input, tools, stream
        case maxOutputTokens = "max_output_tokens"
    }

    /// Building the body may have to fetch bytes a part points at, which is
    /// why it is asynchronous and why a provider needs no store of its own.
    init(model: String, request: ModelRequest, maxOutputTokens: Int) async throws {
        self.model = model
        self.stream = true
        self.maxOutputTokens = maxOutputTokens
        self.tools = request.tools.map(ToolSpec.init)
        var input: [InputItem] = []
        for message in request.messages {
            input += try await InputItem.items(for: message, resolving: request.content)
        }
        self.input = input
    }

    func encoded() throws -> Data { try JSONEncoder().encode(self) }

    struct ToolSpec: Encodable {
        let type = "function"
        let name: String
        let description: String
        let parameters: JSONText

        init(_ definition: ToolDefinition) {
            name = definition.name
            description = definition.description
            parameters = JSONText(definition.parameters)
        }
    }

    /// One item of the `input` array. A message, a call the model made, or the
    /// result of one.
    enum InputItem: Encodable {
        /// One message and its parts, which may be words and pictures at once.
        case message(role: String, parts: [Part])
        case functionCall(callID: String, name: String, arguments: String)
        case functionCallOutput(callID: String, output: String)

        /// One part on the wire: the vendor's name for it, and its value.
        enum Part: Encodable {
            case text(type: String, String)
            case image(dataURL: String)
            case imageURL(String)

            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: Key.self)
                switch self {
                case .text(let type, let text):
                    try container.encode(type, forKey: .type)
                    try container.encode(text, forKey: .text)
                case .image(let dataURL):
                    try container.encode("input_image", forKey: .type)
                    try container.encode(dataURL, forKey: .imageURL)
                case .imageURL(let url):
                    try container.encode("input_image", forKey: .type)
                    try container.encode(url, forKey: .imageURL)
                }
            }

            private enum Key: String, CodingKey {
                case type, text
                case imageURL = "image_url"
            }
        }

        static func items(
            for message: Message,
            resolving content: (any ContentStore)?
        ) async throws -> [InputItem] {
            switch message {
            case .system(let text):
                return [.message(role: "system", parts: [.text(type: "input_text", text)])]
            case .user(let parts):
                return [.message(role: "user", parts: try await wire(parts, "input_text", resolving: content))]
            case .assistant(let parts, let calls):
                var items: [InputItem] = []
                let wired = try await wire(parts, "output_text", resolving: content)
                if !wired.isEmpty {
                    items.append(.message(role: "assistant", parts: wired))
                }
                items += calls.map {
                    .functionCall(callID: $0.id, name: $0.name, arguments: $0.arguments)
                }
                return items
            case .toolResult(let result):
                return [.functionCallOutput(callID: result.callID, output: result.content)]
            }
        }

        /// Turns swaco's parts into the vendor's, fetching whatever points
        /// elsewhere. Reasoning and citations are the model's own and are not
        /// sent back to it; a part this protocol cannot carry is left out
        /// rather than guessed at.
        private static func wire(
            _ parts: [ContentPart],
            _ textType: String,
            resolving content: (any ContentStore)?
        ) async throws -> [Part] {
            var wired: [Part] = []
            for part in parts {
                switch part {
                case .text(let text) where !text.isEmpty:
                    wired.append(.text(type: textType, text))
                case .image(let source):
                    wired.append(try await image(source, resolving: content))
                case .text, .reasoning, .citation, .providerTool, .providerToolResult:
                    continue
                }
            }
            return wired
        }

        private static func image(
            _ source: ContentSource,
            resolving content: (any ContentStore)?
        ) async throws -> Part {
            switch source {
            case .bytes(let data, let type):
                return .image(dataURL: "data:\(type);base64,\(data.base64EncodedString())")
            case .url(let url, _):
                return .imageURL(url.absoluteString)
            case .reference(let reference):
                guard let content else { throw ProviderError.noContentStore(reference) }
                let data = try await content.load(reference)
                return .image(dataURL: "data:\(reference.type);base64,\(data.base64EncodedString())")
            }
        }

        private enum Key: String, CodingKey {
            case role, content, type, callID = "call_id", name, arguments, output, text
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: Key.self)
            switch self {
            case .message(let role, let parts):
                try container.encode(role, forKey: .role)
                try container.encode(parts, forKey: .content)
            case .functionCall(let callID, let name, let arguments):
                try container.encode("function_call", forKey: .type)
                try container.encode(callID, forKey: .callID)
                try container.encode(name, forKey: .name)
                try container.encode(arguments, forKey: .arguments)
            case .functionCallOutput(let callID, let output):
                try container.encode("function_call_output", forKey: .type)
                try container.encode(callID, forKey: .callID)
                try container.encode(output, forKey: .output)
            }
        }
    }
}

/// JSON the app already wrote, passed through without being modelled.
struct JSONText: Encodable {
    let text: String
    init(_ text: String) { self.text = text }

    func encode(to encoder: any Encoder) throws {
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
        let data = try JSONSerialization.data(withJSONObject: object)
        var container = encoder.singleValueContainer()
        try container.encode(RawJSON(data: data))
    }

    /// Encodes bytes that are already JSON. `JSONEncoder` has no such door, so
    /// the value is decoded once and re-encoded through `AnyJSON`.
    private struct RawJSON: Encodable {
        let data: Data
        func encode(to encoder: any Encoder) throws {
            let value = try JSONDecoder().decode(AnyJSON.self, from: data)
            try value.encode(to: encoder)
        }
    }
}

/// Any JSON value, so schemas the app wrote survive a round trip unchanged.
enum AnyJSON: Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([AnyJSON])
    case object([String: AnyJSON])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([AnyJSON].self) { self = .array(value) }
        else { self = .object(try container.decode([String: AnyJSON].self)) }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}
