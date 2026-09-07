import Foundation
import Swaco

/// Stops a loop after a chosen number of turns, or a chosen length of time.
///
/// A template, not a shipped extension: what a budget should be, and what
/// should happen when it runs out, are product decisions. Copy this into your
/// app and change it freely.
///
/// The door it uses is the refusal at the end of a turn, which is the only
/// moment a loop can be stopped between turns without anything being lost.
public struct Budget: Extension {
    public let name = "budget"
    private let turns: Int?
    private let time: Duration?
    private let started: @Sendable () -> ContinuousClock.Instant

    public init(
        turns: Int? = nil,
        time: Duration? = nil,
        clock: ContinuousClock = ContinuousClock()
    ) {
        self.turns = turns
        self.time = time
        let start = clock.now
        self.started = { start }
    }

    public func turnEnded(_ turn: Int, in context: ExtensionContext) async -> Verdict {
        if let turns, turn >= turns {
            return .refuse("the budget of \(turns) turns is spent")
        }
        if let time, ContinuousClock().now - started() >= time {
            return .refuse("the budget of \(time) is spent")
        }
        return .pass
    }
}

/// A budget that spends what the process has left rather than a number chosen
/// in advance. On a phone this is often the honest one: an app extension has a
/// few seconds, and a loop that ignores that is a loop that gets killed
/// mid-turn.
public struct RemainingTimeBudget: Extension {
    public let name = "remaining-time"
    /// How much of what is left to keep back for finishing up.
    private let reserve: TimeInterval

    public init(reserve: TimeInterval = 3) {
        self.reserve = reserve
    }

    public func turnEnded(_ turn: Int, in context: ExtensionContext) async -> Verdict {
        guard let remaining = context.execution.remainingTime else { return .pass }
        guard remaining > reserve else {
            return .refuse("only \(Int(remaining))s of this process is left")
        }
        return .pass
    }
}
