import Foundation
import Swaco

/// Turns the Responses protocol's server-sent events into swaco's canonical
/// stream events. Pure, so the recorded fixtures test the same code the wire
/// runs.
public struct ResponsesEventMapper: Sendable {
    private var sawToolCall = false

    public init() {}

    public mutating func map(_ event: ServerSentEvent) throws -> [StreamEvent] {
        guard !event.data.isEmpty, event.data != "[DONE]" else { return [] }
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: Data(event.data.utf8))
        } catch {
            throw ProviderError.malformed(event.data)
        }

        switch payload.type {
        case "response.output_text.delta":
            guard let delta = payload.delta, !delta.isEmpty else { return [] }
            return [.text(delta)]

        case "response.output_item.done":
            guard let item = payload.item, item.type == "function_call",
                  let id = item.callID, let name = item.name else { return [] }
            sawToolCall = true
            return [.toolCall(ToolCall(id: id, name: name, arguments: item.arguments ?? "{}"))]

        case "response.completed":
            if payload.response?.incompleteDetails?.reason != nil { return [.stop(.maxTokens)] }
            return [.stop(sawToolCall ? .toolUse : .endTurn)]

        case "response.incomplete":
            return [.stop(.maxTokens)]

        case "response.failed", "error":
            let failure = payload.error ?? payload.response?.error
            throw ProviderError.vendor(
                type: failure?.type ?? "unknown",
                message: failure?.message ?? event.data
            )

        default:
            return []
        }
    }

    private struct Payload: Decodable {
        let type: String
        let delta: String?
        let item: Item?
        let response: Summary?
        let error: Failure?

        struct Item: Decodable {
            let type: String
            let callID: String?
            let name: String?
            let arguments: String?
            enum CodingKeys: String, CodingKey {
                case type, name, arguments
                case callID = "call_id"
            }
        }

        struct Summary: Decodable {
            let incompleteDetails: Incomplete?
            let error: Failure?
            enum CodingKeys: String, CodingKey {
                case error
                case incompleteDetails = "incomplete_details"
            }
            struct Incomplete: Decodable { let reason: String? }
        }

        struct Failure: Decodable {
            let type: String?
            let message: String?
        }
    }
}
