import Foundation
import Swaco

/// Stops a loop after a turn and leaves the rest to a later process.
///
/// This is the shape of work on a phone. A share sheet has seconds. A
/// background wake-up is expected to give its time back. An app that is about
/// to be suspended would rather stop between turns than be killed inside one.
/// None of that loses anything: the log says the loop was handed over, and
/// whatever runs next resumes it, tools that were waiting included.
///
/// What counts as a good moment to stop is the app's, so the rule is the
/// app's. Two are named below because they are the common two.
public struct Handover: Extension {
    public let name = "handover"
    /// Given the turn just finished and where the loop is running, whether to
    /// stop here and leave the rest.
    public typealias Rule = @Sendable (Int, ExecutionContext) -> String?

    private let rule: Rule

    public init(rule: @escaping Rule) {
        self.rule = rule
    }

    /// One turn, then hand over. What a share sheet or an intent wants: do the
    /// thinking the person is waiting for and let the app finish the rest.
    public static let afterOneTurn = Handover { turn, _ in
        turn >= 1 ? "one turn is this process's share" : nil
    }

    /// Hand over while there is still time to do it tidily. The honest rule
    /// for an app extension, which is told how long it has.
    public static func whenTimeIsShort(reserve: TimeInterval = 5) -> Handover {
        Handover { _, execution in
            guard let remaining = execution.remainingTime, remaining <= reserve else { return nil }
            return "only \(Int(remaining))s of this process is left"
        }
    }

    public func turnEnded(_ turn: Int, in context: ExtensionContext) async -> Verdict {
        guard let reason = rule(turn, context.execution) else { return .pass }
        return .handOver(reason)
    }
}
