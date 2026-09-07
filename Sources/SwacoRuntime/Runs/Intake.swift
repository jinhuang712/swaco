import Foundation
import Swaco

/// The runtime's answer to the arrival hook: a rule the app writes over facts
/// swaco declares, and nothing else.
///
/// The facts are where the event came from and what the loop was doing when it
/// landed. The decision is the app's: a notification arriving while the agent
/// is waiting on a person may belong in this conversation, or may be its own
/// piece of work, and no product would answer that the same way.
///
/// An app that lists no intake extension gets a new run for every event that
/// arrives during another, because with nobody holding an opinion an arrival
/// is left.
public struct Intake: Extension {
    public let name = "intake"
    /// Given what arrived and what the loop was doing, where it goes.
    public typealias Rule = @Sendable (InboundEvent, Situation) -> Arrival

    /// What the loop was doing when something arrived.
    public struct Situation: Sendable, Hashable {
        public let turn: Int
        public let waitingForResult: Bool
        public let execution: ExecutionContext
    }

    private let rule: Rule

    public init(rule: @escaping Rule) {
        self.rule = rule
    }

    /// Everything joins the conversation it arrived into. The simplest rule
    /// there is, and the one a chat wants.
    public static let intoTheConversation = Intake { _, _ in .inject }

    /// A person's words join the conversation; everything else is its own
    /// piece of work. The rule an app with more than a chat tends to want.
    public static let peopleInterruptOthersDoNot = Intake { inbound, _ in
        inbound.source == .person ? .inject : .leave
    }

    public func arrived(_ inbound: InboundEvent, in context: ExtensionContext) async -> Arrival? {
        rule(inbound, Situation(
            turn: context.turn,
            waitingForResult: context.waitingForResult,
            execution: context.execution
        ))
    }
}
