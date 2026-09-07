import Foundation

/// How the thing an extension acted on is written down: a word, and the
/// identity of what it was where there is one.
extension Subject: Codable {
    private enum Key: String, CodingKey {
        case what, id, turn
    }

    private enum What {
        static let request = "request"
        static let response = "response"
        static let toolCall = "tool_call"
        static let toolResult = "tool_result"
        static let turn = "turn"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        switch try container.decode(String.self, forKey: .what) {
        case What.request: self = .request
        case What.response: self = .response
        case What.toolCall: self = .toolCall(try container.decode(String.self, forKey: .id))
        case What.toolResult: self = .toolResult(try container.decode(String.self, forKey: .id))
        case What.turn: self = .turn(try container.decode(Int.self, forKey: .turn))
        case let other:
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "unknown subject: \(other)"
            ))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        switch self {
        case .request:
            try container.encode(What.request, forKey: .what)
        case .response:
            try container.encode(What.response, forKey: .what)
        case .toolCall(let id):
            try container.encode(What.toolCall, forKey: .what)
            try container.encode(id, forKey: .id)
        case .toolResult(let id):
            try container.encode(What.toolResult, forKey: .what)
            try container.encode(id, forKey: .id)
        case .turn(let turn):
            try container.encode(What.turn, forKey: .what)
            try container.encode(turn, forKey: .turn)
        }
    }
}
