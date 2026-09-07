import Foundation
import Swaco

/// Keeps a long history inside a model's context by replacing the oldest part
/// of it with a summary.
///
/// A template, not a shipped extension, and the clearest case of why: what may
/// be forgotten, what must be kept word for word, and who writes the summary
/// are decisions no library should make for a product.
///
/// The door it uses is rewriting the request. The log is untouched: compaction
/// changes what the model is sent, never what happened.
public struct Compaction: Extension {
    public let name = "compaction"
    /// Above this many messages, the oldest are summarised.
    private let limit: Int
    /// How many of the most recent messages are always sent as they are.
    private let keep: Int
    /// Who writes the summary. An app may call a small model, or write it
    /// itself; the template joins the text, which is honest and dull.
    private let summarise: @Sendable ([Message]) async -> String

    public init(
        limit: Int = 40,
        keep: Int = 10,
        summarise: @Sendable @escaping ([Message]) async -> String = Compaction.joined
    ) {
        self.limit = limit
        self.keep = keep
        self.summarise = summarise
    }

    public func beforeRequest(
        _ request: ModelRequest,
        in context: ExtensionContext
    ) async -> Decision<ModelRequest> {
        let messages = request.messages
        guard messages.count > limit else { return .pass }

        // Standing instructions are not history and are never summarised.
        let instructions = messages.prefix { if case .system = $0 { true } else { false } }
        let history = messages.dropFirst(instructions.count)
        guard history.count > keep else { return .pass }

        let older = Array(history.dropLast(keep))
        let recent = Array(history.suffix(keep))
        let summary = Message.system("Earlier in this conversation: \(await summarise(older))")
        return .rewrite(ModelRequest(
            messages: Array(instructions) + [summary] + recent,
            tools: request.tools
        ))
    }

    /// The dullest summary there is: what was said, joined. An app replaces
    /// this with something better.
    public static let joined: @Sendable ([Message]) async -> String = { messages in
        messages.compactMap { message in
            switch message {
            case .system(let text): "instructions: \(text)"
            case .user(let text): "the person said: \(text)"
            case .assistant(let text, let calls) where !text.isEmpty:
                calls.isEmpty ? "the agent said: \(text)" : "the agent said: \(text), and used \(calls.count) tools"
            case .assistant(_, let calls): "the agent used \(calls.count) tools"
            case .toolResult(let result): "a tool returned: \(result.content)"
            }
        }
        .joined(separator: " ")
    }
}
