import Foundation
import Swaco

/// Turns the chat-completions protocol's chunks into swaco's stream events.
///
/// The work this protocol needs and the newer one does not is assembly: a tool
/// call arrives as a name, then its arguments in fragments, sometimes a single
/// brace at a time. The call is complete only when the turn ends, so it is
/// held here until then and handed over whole.
public struct ChatCompletionsEventMapper: Sendable {
    private var assembling: [Int: Assembling] = [:]
    private var stopping: StopReason?
    private var finished = false

    public init() {}

    public mutating func map(_ event: ServerSentEvent) throws -> [StreamEvent] {
        guard !event.data.isEmpty else { return [] }
        guard event.data != "[DONE]" else { return done() }

        let chunk: Chunk
        do {
            chunk = try JSONDecoder().decode(Chunk.self, from: Data(event.data.utf8))
        } catch {
            throw ProviderError.malformed(event.data)
        }
        if let failure = chunk.error {
            throw ProviderError.vendor(type: failure.type ?? "unknown",
                                       message: failure.message ?? event.data)
        }

        var events: [StreamEvent] = []
        for choice in chunk.choices ?? [] {
            if let text = choice.delta?.content, !text.isEmpty {
                events.append(.text(text))
            }
            // Some vendors stream their thinking beside the answer.
            if let thought = choice.delta?.reasoningContent, !thought.isEmpty {
                events.append(.reasoning(thought))
            }
            for fragment in choice.delta?.toolCalls ?? [] {
                assemble(fragment)
            }
            if let reason = choice.finishReason {
                // The turn is over, so the calls are whole. The stop itself
                // waits: this protocol sends what the turn cost afterwards,
                // and swaco says the same things in the same order whoever
                // is speaking.
                events += handOverCalls()
                stopping = reason == "length" ? .maxTokens : nil
            }
        }
        if let usage = chunk.usage {
            events.append(.usage(usage.normalised))
        }
        return events
    }

    /// The end of the stream, whether the vendor announced it or the
    /// connection simply finished. Anything still held is handed over, and
    /// the stop is said last.
    public mutating func done() -> [StreamEvent] {
        guard !finished else { return [] }
        finished = true
        var events = handOverCalls()
        events.append(.stop(stopping ?? (sawCalls ? .toolUse : .endTurn)))
        return events
    }

    /// Calls are complete only when the turn ends, so they are handed over
    /// then, whole, and only once.
    private mutating func handOverCalls() -> [StreamEvent] {
        let held = assembling
        assembling = [:]
        return held.keys.sorted().compactMap { index in
            guard let call = held[index], let id = call.id, let name = call.name else { return nil }
            sawCalls = true
            return .toolCall(ToolCall(
                id: id, name: name,
                arguments: call.arguments.isEmpty ? "{}" : call.arguments
            ))
        }
    }

    private mutating func assemble(_ fragment: Chunk.Choice.Delta.ToolCall) {
        let index = fragment.index ?? 0
        var held = assembling[index] ?? Assembling()
        held.id = fragment.id ?? held.id
        held.name = fragment.function?.name ?? held.name
        held.arguments += fragment.function?.arguments ?? ""
        assembling[index] = held
    }

    private var sawCalls = false

    private struct Assembling {
        var id: String?
        var name: String?
        var arguments = ""
    }

    private struct Chunk: Decodable {
        let choices: [Choice]?
        let usage: Counts?
        let error: Failure?

        struct Choice: Decodable {
            let delta: Delta?
            let finishReason: String?
            enum CodingKeys: String, CodingKey {
                case delta
                case finishReason = "finish_reason"
            }

            struct Delta: Decodable {
                let content: String?
                let reasoningContent: String?
                let toolCalls: [ToolCall]?
                enum CodingKeys: String, CodingKey {
                    case content
                    case reasoningContent = "reasoning_content"
                    case toolCalls = "tool_calls"
                }

                struct ToolCall: Decodable {
                    let index: Int?
                    let id: String?
                    let function: Function?
                    struct Function: Decodable {
                        let name: String?
                        let arguments: String?
                    }
                }
            }
        }

        struct Counts: Decodable {
            let promptTokens: Int?
            let completionTokens: Int?
            let promptTokensDetails: Cached?
            let completionTokensDetails: Reasoning?

            enum CodingKeys: String, CodingKey {
                case promptTokens = "prompt_tokens"
                case completionTokens = "completion_tokens"
                case promptTokensDetails = "prompt_tokens_details"
                case completionTokensDetails = "completion_tokens_details"
            }

            struct Cached: Decodable {
                let cachedTokens: Int?
                enum CodingKeys: String, CodingKey { case cachedTokens = "cached_tokens" }
            }

            struct Reasoning: Decodable {
                let reasoningTokens: Int?
                enum CodingKeys: String, CodingKey { case reasoningTokens = "reasoning_tokens" }
            }

            var normalised: Usage {
                Usage(
                    inputTokens: promptTokens ?? 0,
                    outputTokens: completionTokens ?? 0,
                    cachedInputTokens: promptTokensDetails?.cachedTokens ?? 0,
                    reasoningTokens: completionTokensDetails?.reasoningTokens ?? 0
                )
            }
        }

        struct Failure: Decodable {
            let type: String?
            let message: String?
        }
    }
}
