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

    init(model: String, request: ModelRequest, maxOutputTokens: Int) {
        self.model = model
        self.stream = true
        self.maxOutputTokens = maxOutputTokens
        self.tools = request.tools.map(ToolSpec.init)
        self.input = request.messages.flatMap(InputItem.items(for:))
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
        case text(role: String, part: String, text: String)
        case functionCall(callID: String, name: String, arguments: String)
        case functionCallOutput(callID: String, output: String)

        static func items(for message: Message) -> [InputItem] {
            switch message {
            case .system(let text):
                return [.text(role: "system", part: "input_text", text: text)]
            case .user(let text):
                return [.text(role: "user", part: "input_text", text: text)]
            case .assistant(let text, let calls):
                var items: [InputItem] = []
                if !text.isEmpty {
                    items.append(.text(role: "assistant", part: "output_text", text: text))
                }
                items += calls.map {
                    .functionCall(callID: $0.id, name: $0.name, arguments: $0.arguments)
                }
                return items
            case .toolResult(let result):
                return [.functionCallOutput(callID: result.callID, output: result.content)]
            }
        }

        private enum Key: String, CodingKey {
            case role, content, type, callID = "call_id", name, arguments, output, text
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: Key.self)
            switch self {
            case .text(let role, let part, let text):
                try container.encode(role, forKey: .role)
                var content = container.nestedUnkeyedContainer(forKey: .content)
                var entry = content.nestedContainer(keyedBy: Key.self)
                try entry.encode(part, forKey: .type)
                try entry.encode(text, forKey: .text)
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
