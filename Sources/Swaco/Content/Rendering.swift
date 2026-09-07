import Foundation

/// How an inbound event becomes something a model can read. The step the loop
/// takes between an event and a request, and the one an app is most likely to
/// want its own version of: replaceable whole, through this protocol.
public protocol EventRendering: Sendable {
    func render(_ inbound: InboundEvent) -> Message
}

/// The default: what a person typed is the message; anything else says where
/// it came from, so the model and the extensions can tell a person's words
/// from what the system delivered.
public struct DefaultEventRendering: EventRendering {
    public init() {}

    public func render(_ inbound: InboundEvent) -> Message {
        switch inbound.source {
        case .person:
            return .user(inbound.text)
        case .shortcut, .notification, .url, .share, .system, .schedule, .sensor:
            return .user("[\(name(of: inbound.source))] \(inbound.text)")
        }
    }

    private func name(of source: Source) -> String {
        Source.wireNames.first { $0.0 == source }?.1 ?? "source"
    }
}

public extension Message {
    /// The context a model is sent, projected from the events that happened.
    /// Messages are not stored: they are read off the log, so there is one
    /// record and no second version of the truth.
    static func projection(
        of events: [Event],
        rendering: some EventRendering = DefaultEventRendering()
    ) -> [Message] {
        var messages: [Message] = []
        var text = ""
        var calls: [ToolCall] = []

        func closeTurn() {
            guard !text.isEmpty || !calls.isEmpty else { return }
            messages.append(.assistant(text: text, toolCalls: calls))
            text = ""
            calls = []
        }

        for event in events {
            switch event {
            case .arrived(let inbound):
                closeTurn()
                messages.append(rendering.render(inbound))
            case .text(let piece):
                text += piece
            case .toolCallIssued(let call):
                calls.append(call)
            case .turnEnded:
                closeTurn()
            case .toolResultArrived(let result):
                closeTurn()
                messages.append(.toolResult(result))
            case .turnStarted, .toolCallDeferred, .cancelled, .failed, .finished, .unrecognised:
                // A turn interrupted before it ended is closed by whatever
                // comes next; nothing received is discarded.
                continue
            }
        }
        closeTurn()
        return messages
    }

    /// The calls that were issued and never answered. What recovery hands
    /// back to the tools that registered them.
    static func unanswered(in events: [Event]) -> [ToolCall] {
        var issued: [ToolCall] = []
        var answered: Set<String> = []
        for event in events {
            switch event {
            case .toolCallIssued(let call): issued.append(call)
            case .toolResultArrived(let result): answered.insert(result.callID)
            default: continue
            }
        }
        return issued.filter { !answered.contains($0.id) }
    }
}
