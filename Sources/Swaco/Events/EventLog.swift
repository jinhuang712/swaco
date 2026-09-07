import Foundation

/// The event log format: how an event is written down.
///
/// This is public API on the same terms as the Swift API. The names below are
/// stable and new ones arrive by addition. An event whose type this version
/// does not know is kept as it was written and written back unchanged, so a
/// log always survives a round trip through a swaco older than the one that
/// wrote it.
extension Event: Codable {
    /// The names on the wire. They do not change.
    enum Name {
        static let turnStarted = "turn_started"
        static let text = "text"
        static let toolCallIssued = "tool_call_issued"
        static let toolCallDeferred = "tool_call_deferred"
        static let toolResultArrived = "tool_result_arrived"
        static let turnEnded = "turn_ended"
        static let cancelled = "cancelled"
        static let failed = "failed"
        static let finished = "finished"
    }

    private enum Key: String, CodingKey {
        case type, turn, text, call, result, stop, origin, partial, message
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        switch try container.decode(String.self, forKey: .type) {
        case Name.turnStarted:
            self = .turnStarted(try container.decode(Int.self, forKey: .turn))
        case Name.text:
            self = .text(try container.decode(String.self, forKey: .text))
        case Name.toolCallIssued:
            self = .toolCallIssued(try container.decode(ToolCall.self, forKey: .call))
        case Name.toolCallDeferred:
            self = .toolCallDeferred(try container.decode(ToolCall.self, forKey: .call))
        case Name.toolResultArrived:
            self = .toolResultArrived(try container.decode(ToolResult.self, forKey: .result))
        case Name.turnEnded:
            self = .turnEnded(try container.decode(StopReason.self, forKey: .stop))
        case Name.cancelled:
            self = .cancelled(
                try container.decode(CancellationOrigin.self, forKey: .origin),
                partial: try container.decode(String.self, forKey: .partial)
            )
        case Name.failed:
            self = .failed(try container.decode(String.self, forKey: .message))
        case Name.finished:
            self = .finished
        case let type:
            // Not ours to understand, and not ours to lose.
            let object = try decoder.singleValueContainer().decode([String: JSONValue].self)
            self = .unrecognised(type: type, fields: object.filter { $0.key != Key.type.rawValue })
        }
    }

    public func encode(to encoder: any Encoder) throws {
        if case .unrecognised(let type, let fields) = self {
            var object = fields
            object[Key.type.rawValue] = .string(type)
            var single = encoder.singleValueContainer()
            try single.encode(object)
            return
        }
        var container = encoder.container(keyedBy: Key.self)
        switch self {
        case .turnStarted(let turn):
            try container.encode(Name.turnStarted, forKey: .type)
            try container.encode(turn, forKey: .turn)
        case .text(let text):
            try container.encode(Name.text, forKey: .type)
            try container.encode(text, forKey: .text)
        case .toolCallIssued(let call):
            try container.encode(Name.toolCallIssued, forKey: .type)
            try container.encode(call, forKey: .call)
        case .toolCallDeferred(let call):
            try container.encode(Name.toolCallDeferred, forKey: .type)
            try container.encode(call, forKey: .call)
        case .toolResultArrived(let result):
            try container.encode(Name.toolResultArrived, forKey: .type)
            try container.encode(result, forKey: .result)
        case .turnEnded(let stop):
            try container.encode(Name.turnEnded, forKey: .type)
            try container.encode(stop, forKey: .stop)
        case .cancelled(let origin, let partial):
            try container.encode(Name.cancelled, forKey: .type)
            try container.encode(origin, forKey: .origin)
            try container.encode(partial, forKey: .partial)
        case .failed(let message):
            try container.encode(Name.failed, forKey: .type)
            try container.encode(message, forKey: .message)
        case .finished:
            try container.encode(Name.finished, forKey: .type)
        case .unrecognised:
            preconditionFailure("handled above")
        }
    }
}

/// A value written down as one stable string.
protocol WireNamed: Codable, Hashable {
    static var wireNames: [(Self, String)] { get }
}

extension WireNamed {
    public init(from decoder: any Decoder) throws {
        let name = try decoder.singleValueContainer().decode(String.self)
        guard let value = Self.wireNames.first(where: { $0.1 == name })?.0 else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "unknown \(Self.self): \(name)"
            ))
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Self.wireNames.first { $0.0 == self }!.1)
    }
}

extension StopReason: WireNamed {
    static var wireNames: [(StopReason, String)] {
        [(.endTurn, "end_turn"), (.toolUse, "tool_use"), (.maxTokens, "max_tokens")]
    }
}

extension CancellationOrigin: WireNamed {
    static var wireNames: [(CancellationOrigin, String)] {
        [(.person, "person"), (.system, "system")]
    }
}
