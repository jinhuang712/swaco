import Foundation

/// How a streamed event is written down, for a recording that is replayed
/// instead of asked for again. Stable names, new ones by addition.
extension StreamEvent: Codable {
    enum Name {
        static let text = "text"
        static let toolCall = "tool_call"
        static let reasoning = "reasoning"
        static let usage = "usage"
        static let stop = "stop"
    }

    private enum Key: String, CodingKey {
        case type, text, call, usage, stop
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        switch try container.decode(String.self, forKey: .type) {
        case Name.text:
            self = .text(try container.decode(String.self, forKey: .text))
        case Name.toolCall:
            self = .toolCall(try container.decode(ToolCall.self, forKey: .call))
        case Name.reasoning:
            self = .reasoning(try container.decode(String.self, forKey: .text))
        case Name.usage:
            self = .usage(try container.decode(Usage.self, forKey: .usage))
        case Name.stop:
            self = .stop(try container.decode(StopReason.self, forKey: .stop))
        case let other:
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "unknown stream event: \(other)"
            ))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        switch self {
        case .text(let text):
            try container.encode(Name.text, forKey: .type)
            try container.encode(text, forKey: .text)
        case .toolCall(let call):
            try container.encode(Name.toolCall, forKey: .type)
            try container.encode(call, forKey: .call)
        case .reasoning(let thought):
            try container.encode(Name.reasoning, forKey: .type)
            try container.encode(thought, forKey: .text)
        case .usage(let usage):
            try container.encode(Name.usage, forKey: .type)
            try container.encode(usage, forKey: .usage)
        case .stop(let reason):
            try container.encode(Name.stop, forKey: .type)
            try container.encode(reason, forKey: .stop)
        }
    }
}
