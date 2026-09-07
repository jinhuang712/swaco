import Foundation
import Swaco

/// Turns the Messages protocol's server-sent events into swaco's.
///
/// Content arrives as numbered blocks that open, receive deltas and close, so
/// what is held here is which block is which: text, a tool call being spelled
/// out, or the model's own thinking.
public struct MessagesEventMapper: Sendable {
    private var open: [Int: Block] = [:]
    private var usage = Usage()
    private var sawToolUse = false

    public init() {}

    public mutating func map(_ event: ServerSentEvent) throws -> [StreamEvent] {
        guard !event.data.isEmpty else { return [] }
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: Data(event.data.utf8))
        } catch {
            throw ProviderError.malformed(event.data)
        }

        switch payload.type {
        case "message_start":
            if let counts = payload.message?.usage { usage = usage + counts.normalised }
            return []

        case "content_block_start":
            guard let index = payload.index, let block = payload.contentBlock else { return [] }
            switch block.type {
            case "tool_use":
                sawToolUse = true
                open[index] = .toolUse(id: block.id ?? "", name: block.name ?? "", input: "")
            case "thinking":
                open[index] = .thinking
            default:
                open[index] = .text
            }
            return []

        case "content_block_delta":
            guard let index = payload.index, let delta = payload.delta else { return [] }
            switch delta.type {
            case "text_delta":
                return delta.text.map { [.text($0)] } ?? []
            case "thinking_delta":
                return delta.thinking.map { [.reasoning($0)] } ?? []
            case "input_json_delta":
                if case .toolUse(let id, let name, let input) = open[index] {
                    open[index] = .toolUse(id: id, name: name, input: input + (delta.partialJSON ?? ""))
                }
                return []
            default:
                return []
            }

        case "content_block_stop":
            guard let index = payload.index else { return [] }
            defer { open[index] = nil }
            guard case .toolUse(let id, let name, let input) = open[index] else { return [] }
            return [.toolCall(ToolCall(id: id, name: name, arguments: input.isEmpty ? "{}" : input))]

        case "message_delta":
            if let counts = payload.usage { usage = usage + counts.normalised }
            guard let reason = payload.delta?.stopReason else { return [] }
            return [.usage(usage), .stop(Self.stop(reason, sawToolUse: sawToolUse))]

        case "error":
            throw ProviderError.vendor(
                type: payload.error?.type ?? "unknown",
                message: payload.error?.message ?? event.data
            )

        default:
            return []
        }
    }

    private static func stop(_ reason: String, sawToolUse: Bool) -> StopReason {
        switch reason {
        case "tool_use": .toolUse
        case "max_tokens": .maxTokens
        default: sawToolUse ? .toolUse : .endTurn
        }
    }

    private enum Block {
        case text
        case thinking
        case toolUse(id: String, name: String, input: String)
    }

    private struct Payload: Decodable {
        let type: String
        let index: Int?
        let delta: Delta?
        let contentBlock: ContentBlock?
        let message: Message?
        let usage: Counts?
        let error: Failure?

        enum CodingKeys: String, CodingKey {
            case type, index, delta, message, usage, error
            case contentBlock = "content_block"
        }

        struct Delta: Decodable {
            let type: String?
            let text: String?
            let thinking: String?
            let partialJSON: String?
            let stopReason: String?
            enum CodingKeys: String, CodingKey {
                case type, text, thinking
                case partialJSON = "partial_json"
                case stopReason = "stop_reason"
            }
        }

        struct ContentBlock: Decodable {
            let type: String
            let id: String?
            let name: String?
        }

        struct Message: Decodable {
            let usage: Counts?
        }

        struct Counts: Decodable {
            let inputTokens: Int?
            let outputTokens: Int?
            let cacheReadInputTokens: Int?
            enum CodingKeys: String, CodingKey {
                case inputTokens = "input_tokens"
                case outputTokens = "output_tokens"
                case cacheReadInputTokens = "cache_read_input_tokens"
            }
            var normalised: Usage {
                Usage(
                    inputTokens: inputTokens ?? 0,
                    outputTokens: outputTokens ?? 0,
                    cachedInputTokens: cacheReadInputTokens ?? 0
                )
            }
        }

        struct Failure: Decodable {
            let type: String?
            let message: String?
        }
    }
}
