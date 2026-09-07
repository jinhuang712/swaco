import Foundation
import Swaco

/// How many runs an app will have going at once.
///
/// Several agents at once is ordinary, and the app stays in control of them:
/// it says the number, because what a phone can carry while a person is
/// waiting is a product judgement and not ours. There is no default, and an
/// app that never passes one is never limited.
///
/// A run holds a place while it records and gives it back when it stops, so a
/// run that is waiting on a person is not holding anything: waiting is not
/// working, and a limit that counted it would deadlock an app that asked two
/// questions at once.
public actor RunLimit {
    private let most: Int
    private var busy = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    public init(atMost most: Int) {
        precondition(most > 0, "a limit of none would run nothing")
        self.most = most
    }

    /// How many runs are working now, for an app that wants to say so.
    public var running: Int { busy }
    /// How many are queued behind the limit.
    public var queued: Int { waiting.count }

    func take() async {
        while busy >= most {
            await withCheckedContinuation { waiting.append($0) }
        }
        busy += 1
    }

    func give() {
        busy -= 1
        guard !waiting.isEmpty else { return }
        waiting.removeFirst().resume()
    }
}
