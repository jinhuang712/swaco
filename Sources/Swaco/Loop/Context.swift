/// What a loop starts from: the messages the model will see, the arrival that
/// begins them if there is one, and the calls that were issued and never
/// answered.
///
/// A fresh loop has one message and no waiting calls. A loop being continued
/// after the process that started it is gone has whatever its log projects.
public struct Context: Sendable {
    public var messages: [Message]
    public var arrival: InboundEvent?
    public var waiting: [ToolCall]
    public var turnsSoFar: Int

    public init(
        messages: [Message],
        arrival: InboundEvent? = nil,
        waiting: [ToolCall] = [],
        turnsSoFar: Int = 0
    ) {
        self.messages = messages
        self.arrival = arrival
        self.waiting = waiting
        self.turnsSoFar = turnsSoFar
    }

    /// A loop that begins with something arriving. The arrival is recorded
    /// first, so the log stands on its own.
    public static func beginning(
        _ inbound: InboundEvent,
        rendering: some EventRendering = DefaultEventRendering()
    ) -> Context {
        Context(messages: [rendering.render(inbound)], arrival: inbound)
    }

    /// A loop continued from events already recorded.
    public static func continuing(
        _ events: [Event],
        rendering: some EventRendering = DefaultEventRendering()
    ) -> Context {
        Context(
            messages: Message.projection(of: events, rendering: rendering),
            waiting: Message.unanswered(in: events),
            turnsSoFar: events.reduce(0) { count, event in
                if case .turnStarted = event { count + 1 } else { count }
            }
        )
    }
}
